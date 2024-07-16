require "reline"

class KeyWatcher
  Callback = Struct.new(:key, :description, :block) do
    def call
      block.call
    end

    def print
      "#{key}: #{description}"
    end
  end

  def self.on(key, description, &block)
    @callbacks ||= {}
    @callbacks[key] = Callback.new(key, description, block)
  end

  def self.callbacks
    @callbacks
  end

  def self.print_help
    puts ""
    puts "------------------------------------------------------------------------------------------"
    puts "------------------------------------------------------------------------------------------"
    puts "---- Press a key to run a command, Ctrl-C to quit or Ctrl-Q to stop running suite. ----"
    puts ""
    self.callbacks.each do |_key, callback|
      if callback.key == "1"
        puts "  " + callback.print + " (#{RSpecWatcher.failed_specs.count} failed)"
      else
        puts "  " + callback.print
      end
    end
    puts "  /: search for and run specs with matching contents"
  end

  # TODO: duplicated in rspec-watcher.rb..
  def self.clear_screen
    puts "\e[H\e[2J"
  end

  on('1', 'retry failed') do
    RSpecWatcher.run_specs(RSpecWatcher.failed_specs)
  end

  on('2', 'clear failures') do
    RSpecWatcher.reset_failures
    clear_screen
    print_help
  end

  on('a', 'run all specs') do
    RSpecWatcher.reset_failures
    RSpecWatcher.run_specs(['spec'])
  end

  def start
    Thread.new do
      begin
        original_term_settings = `stty -g`.chomp
        system("stty raw -echo")

        loop do
          # use this instead of STDIN.getch so Ctrl-C can be caught
          # by forked rspec processes for clean exit
          char = STDIN.read_nonblock(1) rescue nil

          # Ctrl-Q
          if char == "\u0011"
            RSpecWatcher.kill_runner
          end

          if char == "\u0003" # Ctrl-C
            if !RSpecWatcher.runner_pid
              exit!(1)
            end

            if RSpecWatcher.wants_to_quit
              exit!(1)
            else
              puts "Press Ctrl-C again to quit"
              RSpecWatcher.kill_runner
              RSpecWatcher.wants_to_quit = true
              # TODO: this needs to quit as soon as the forked process is done
            end
          end

          if char == "/"
            prompt_for_search
          end

          if self.class.callbacks[char]
            self.class.callbacks[char].call
          end

          # TODO: add queue for all console output and print it here
          # That way changing stty settings won't sometimes mangle rspec output.
          # Would require passing queue as logger to rspec I think..

          sleep(0.1)
        end
      ensure
        system("stty #{original_term_settings}")
      end
    end
  end

  def prompt_for_search
    puts ""
    # reline handles terminal mode and switches back when done
    search = Reline.readline("Search regexp (q or Ctrl-C to exit): ", true)
    case search.chomp
    when 'exit', 'quit', 'q'
      KeyWatcher.clear_screen
      KeyWatcher.print_help
    when ''
      # NOOP
    else
      paths = RSpecWatcher::Search.search_for_specs(search)
      RSpecWatcher.run_specs(paths)
    end
  rescue Interrupt
    KeyWatcher.clear_screen
    KeyWatcher.print_help
  end
end
