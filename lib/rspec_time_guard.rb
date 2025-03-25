# frozen_string_literal: true

require 'rspec_time_guard/configuration'
require 'rspec_time_guard/version'
require 'rspec_time_guard/railtie' if defined?(Rails)

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
      Rails.logger.info "[RspecTimeGuard] Setting up RspecTimeGuard"

      RSpec.configure do |config|
        config.around(:each) do |example|
          time_limit_seconds = example.metadata[:time_limit_seconds] || RspecTimeGuard.configuration.global_time_limit_seconds

          next example.run unless time_limit_seconds

          thread = Thread.new do
            Thread.current.report_on_exception = false

            begin
              example.run
            rescue Exception => e
              Thread.current[:exception] = e
            end
          end

          # NOTE: The following logic:
          #  - Waits for the thread to complete
          #  - Returns `true` if thread completed, `nil` if it timed out

          if thread.join(time_limit_seconds)
            raise thread[:exception] if thread[:exception]
          else
            message = "[RspecTimeGuard] Example exceeded timeout of #{time_limit_seconds} seconds"

            if RspecTimeGuard.configuration.continue_on_timeout
              warn "#{message} - Running the example anyway (:continue_on_timeout option set to TRUE)"
              example.run
            else
              # thread.kill
              RspecTimeGuard.terminate_thread(thread)
              raise RspecTimeGuard::TimeLimitExceededError, message
            end
          end
        end
      end
    end

    def terminate_thread(thread)
      return unless thread.alive?

      # Attempt to terminate the thread gracefully
      thread.exit

      # Give the thread a moment to exit gracefully and perform cleanup
      sleep 0.1
      # If it's still alive, kill it
      thread.kill if thread.alive?
    end
  end
end

