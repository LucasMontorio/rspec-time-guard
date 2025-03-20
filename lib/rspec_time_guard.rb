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

          begin
            # NOTE: Creation of a new thread that runs in parallel with the main thread
            #  - The block inside contains the actual test execution (`example.run`)
            #  - Any exceptions in the thread are caught and stored in thread-local storage using `Thread.current[:exception]`
            thread = Thread.new do
              example.run
            end

            # NOTE: The following logic:
            #  - Waits for the thread to complete
            #  - Returns `true` if thread completed, `nil` if it timed out
            unless thread.join(time_limit_seconds)
              message = "[RspecTimeGuard] Example exceeded timeout of #{time_limit_seconds} seconds"

              if RspecTimeGuard.configuration.continue_on_timeout
                warn "#{message} - Running the example anyway (:continue_on_timeout option set to TRUE)"
                example.run
              else
                thread.kill
                raise RspecTimeGuard::TimeLimitExceededError, message
              end
            end
          end
        end
      end
    end
  end
end

