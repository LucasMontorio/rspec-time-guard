# frozen_string_literal: true

require "rspec_time_guard/configuration"
require "rspec_time_guard/version"
require "rspec_time_guard/railtie" if defined?(Rails)

module RspecTimeGuard
  class TimeLimitExceededError < StandardError; end

  class << self
    def configure
      yield(configuration)
    end

    def configuration
      @_configuration ||= RspecTimeGuard::Configuration.new
    end

    def setup
      RSpec.configure do |config|
        config.around(:each) do |example|
          time_limit_seconds = example.metadata[:time_limit_seconds] || RspecTimeGuard.configuration.global_time_limit_seconds

          next example.run unless time_limit_seconds

          completed = false

          # NOTE: We instantiate a monitoring thread, to allow the example to run in the main RSpec thread.
          # This is required to keep the RSpec context.
          monitor_thread = Thread.new do
            Thread.current.report_on_exception = false

            # NOTE: The following logic:
            #  - Waits for the duration of the time limit
            #  - If the main thread is still running at that stage, raises a TimeLimitExceededError
            sleep time_limit_seconds

            unless completed
              message = "[RspecTimeGuard] Example exceeded timeout of #{time_limit_seconds} seconds"
              if RspecTimeGuard.configuration.continue_on_timeout
                warn "#{message} - Running the example anyway (:continue_on_timeout option set to TRUE)"
                example.run
              else
                Thread.main.raise RspecTimeGuard::TimeLimitExceededError, message
              end
            end
          end

          # NOTE: Main RSpec thread execution
          begin
            example.run
            completed = true
          ensure
            # NOTE: We explicitly clean up the monitoring thread in case the example completes before the time limit.
            monitor_thread.kill if monitor_thread.alive?
          end
        end
      end
    end
  end
end
