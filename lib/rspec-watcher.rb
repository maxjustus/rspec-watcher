# frozen_string_literal: true

require 'listen'
require 'rspec/core'

require_relative 'rspec_watcher/version'
require_relative 'rspec_watcher/key_watcher'
require_relative 'rspec_watcher/rg'
require_relative 'rspec_watcher/railtie' if defined?(Rails)

# This allows me to read key presses in a continuous loop without blocking
# by putting the terminal in raw mode without garbling spec run output.
# Raw mode requires that newlines be printed with \r\n instead of just \n
# for the terminal to display them as newlines.
class RawNewlinePrintingRawIO < DelegateClass(IO)
  def initialize
    super(IO.new(1, 'w'))
  end

  def write(data)
    super(translate_newlines(data)[0])
  end

  # puts adds a newline after each arg if it doesn't
  # already end with one
  def puts(*args)
    translate_newlines(*args).each do |arg|
      arg += "\n" unless arg.end_with?("\n")

      write(arg)
    end
  end

  def print(*args)
    super(*translate_newlines(*args))
  end

  def translate_newlines(*args)
    args.map { |arg| arg.gsub("\n", "\r\n") }
  end
end

$stdout = RawNewlinePrintingRawIO.new
$stderr = RawNewlinePrintingRawIO.new

module RSpecWatcher
  SPEC_INFERRER = ->(_modified, _added, _removed) { [] }
  PATH_INFERRER = ->(path) do
    if defined?(Rails)
      Rails.root.join(path)
    else
      path
    end
  end

  @path_inferrer = PATH_INFERRER
  @rules = []
  @queue = Queue.new

  class << self
    attr_accessor :path_inferrer, :running, :failed_specs, :wants_to_quit, :runner_pid
    attr_reader :rules, :queue

    def configure(&block)
      @rules = []
      @failed_specs = []
      instance_exec(&block)
    end

    def watch(path, **options, &inferrer)
      inferrer ||= SPEC_INFERRER
      rules << [path, options, inferrer]
    end

    def on_key(key, description, &block)
      KeyWatcher.on(key, description, &block)
    end

    # TODO: add to readme
    def run_specs_with_matching_constants_in(*paths)
      raise "rg is required to run specs with matching constants" unless system("which rg > /dev/null")

      paths.each do |path|
        watch(path, only: /\.rb\z/) do |modified, added, removed|
          Rg.find_matching_specs(modified + added + removed)
        end
      end
    rescue => e
      puts "Error running specs with matching constants: #{e}"
    end

    # TODO: add to readme
    def run_specs_on_key(key, *paths)
      description = "run #{paths.join(' ')}"

      on_key(key, description) do
        reset_failures
        run_specs(Array(paths))
      end
    end

    # ultimately maybe this should uses curses or something and have a separate
    # pane for output - shiz is too glitchy as it is..
    def start
      # suppress listen logging
      Listen.logger = ::Logger.new('/dev/null', level: ::Logger::UNKNOWN)

      listeners.each(&:start)
      start_runner
      KeyWatcher.new.start
      print_help
    end

    def reset_failures
      @failed_specs = []
    end

    def run_specs(paths)
      queue << paths
    end

    def print_help
      KeyWatcher.print_help
    end

    def kill_runner
      Process.kill('USR1', runner_pid) if runner_pid
    end

    private

    def listeners
      rules.map do |path, options, inferrer|
        Listen.to(path_inferrer.call(path), **options) do |modified, added, removed|
          run_specs(inferrer.call(modified, added, removed))
        end
      end
    end

    def start_runner
      Thread.new do
        while paths = queue.pop
          sleep 0.1 # give file event watchers a chance to enqueue more paths
          # drain the queue and run all specs in one go
          paths += queue.pop until queue.empty?
          paths.uniq!

          begin
            rd_failures, wr_failures = IO.pipe
            rd_exit, wr_exit = IO.pipe

            paths = specs_to_run(paths)

            # we fork on each run to avoid issues with class reloading
            # TODO: update readme to remove bit about disabling cache_classes
            # because forking does away with that need
            pid = fork do
              clear_screen
              puts "Running specs: #{paths.join(' ')}"
              RSpec.world.wants_to_quit = false

              # just doing this directly to avoid multiple prints of "rspec is
              # quitting" from each prspec worker
              trap('USR1') do
                if RSpec.world.wants_to_quit
                  wr_exit.puts 'cancelled'
                  exit!(1)
                else
                  puts "RSpec runner is shutting down. Press Ctrl-Q again to force stop (at_exit hooks will be skipped)."
                  RSpec.world.wants_to_quit = true
                end
              end

              # TODO: change this to an explicit config
              if defined?(ParallelRSpec)
                options = RSpec::Core::ConfigurationOptions.new(paths)
                ParallelRSpec::Runner.new(options).run($stderr, $stdout)
              else
                RSpec::Core::Runner.run(paths)
              end

              wr_failures.puts(Marshal.dump(get_failed_specs))

              if RSpec.world.wants_to_quit
                puts "Run cancelled"
                wr_exit.puts 'cancelled'
              else
                wr_exit.puts 'done'
              end
            end

            self.runner_pid = pid

            done_status = rd_exit.gets.chomp
            if done_status == "cancelled" && self.wants_to_quit
              exit!(1)
            end

            if done_status == "done"
              # deserialize the failed specs from the child spec running process
              @failed_specs = Marshal.load(rd_failures.gets)

              # somehow - make this conditional on ctrl-c being pressed
              # maybe store the pid in a global and send INT to it?
              # Process.kill('INT', pid)
              Process.wait(pid, Process::WNOHANG)
            end

            self.runner_pid = nil

            sleep 0.3

            print_help
          end
        end
      end
    end

    # Filter out nonexistent files and paths to specific lines if the whole file will be rerun
    def specs_to_run(paths)
      # exclude specific line paths if passed directory
      # because rspec will only run specific line args if given both
      # paths and secific lines.
      if paths.any? { |path| File.directory?(path) }
        return paths.reject { |path| path.include?(':') }
      end

      paths = (paths + @failed_specs).reject do |path|
        file_path = path.split(':').first
        next true unless File.exist?(file_path)

        path.include?(':') && paths.include?(file_path)
      end

      paths
    end

    def get_failed_specs
      RSpec
        .world
        .all_examples
        .select(&:exception)
        .map(&:location_rerun_argument)
        .map { |path| File.absolute_path(path) }
    end

    def clear_screen
      puts "\e[H\e[2J"
    end
  end
end
