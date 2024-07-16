# frozen_string_literal: true

require "bundler/gem_tasks"
task default: %i[]

require_relative "lib/rspec-watcher"

task :watch do
  RSpecWatcher.configure do
    watch "spec" do |modified, added, removed|
      modified + added + removed
    end

    watch "lib" do |modified, added, removed|
      puts "Modified: #{modified}"
      paths = modified + added + RSpecWatcher::Rg.find_matching_specs(modified + added + removed)
      paths
    end

    run_specs_on_key 'm', 'spec/models'
    run_specs_on_key 'c', 'spec/controllers'
    run_specs_on_key 'f', 'spec/features'
  end

  RSpecWatcher.start

  sleep
end
