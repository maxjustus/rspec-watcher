# frozen_string_literal: true

require "bundler/gem_tasks"
task default: %i[]

require_relative "lib/rspec-watcher"

task :watch do
  RSpecWatcher.configure do
    watch "spec"

    run_specs_on_key 'm', 'spec/models'
    run_specs_on_key 'c', 'spec/controllers'
    run_specs_on_key 'f', 'spec/features'
    run_specs_with_matching_constants_in 'lib'
  end

  RSpecWatcher.start

  sleep
end
