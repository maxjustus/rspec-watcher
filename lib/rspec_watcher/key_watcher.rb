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
    puts "---- Press a key to run a command or Ctrl-C to quit ----"
    self.callbacks.each do |_key, callback|
      if callback.key == "r"
        puts "  " + callback.print + " (#{RSpecWatcher.failed_specs.count} failed)"
      else
        puts "  " + callback.print
      end
    end
  end

  on('r', 'retry failed') do
    RSpecWatcher.run_specs(RSpecWatcher.failed_specs)
  end

  on('a', 'run all specs') do
    RSpecWatcher.reset_failures
    RSpecWatcher.run_specs(['spec'])
  end

  # add a "/' key to run specs with contents that match a pattern
  # could be cool if it autocompleted to show matches?

  # TODO: escape key to cancel running specs?
  # or - if catching ctrl-C - exit cleanly in spec runs

  def start
    Thread.new do
      loop do
        # use this instead of STDIN.getch so Ctrl-C can be caught
        # by forked rspec processes for clean exit
        system("stty raw -echo")
        char = STDIN.read_nonblock(1) rescue nil
        system("stty -raw echo")

        if self.class.callbacks[char]
          self.class.callbacks[char].call
        end

        # TODO: add queue for all console output and print it here
        # That way changing stty settings won't sometimes mangle rspec output.
        # Would require passing queue as logger to rspec I think..

        sleep(0.1)
      end
    end
  end
end
