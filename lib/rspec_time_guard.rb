# frozen_string_literal: true

module RspecTimeGuard
  class TimeLimitExceededError < StandardError; end

  class << self
    def configure
      yield(configuration)
    end

    def configuration
      @_configuration ||= Configuration.new
    end

    def setup
      Rails.logger.info "[RspecTimeGuard] Setting up RspecTimeGuard"

      RSpec.configure do |config|
        config.around(:each) do |example|
          time_limit_seconds = example.metadata[:time_limit_seconds] || RspecTimeGuard.configuration.max_execution_time

          next example.run unless example.metadata[:time_limit_seconds]

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
              thread.kill
              raise RspecTimeGuard::TimeLimitExceededError,
                    "[RspecTimeGuard] Example exceeded timeout of #{time_limit_seconds} seconds"
            end
          end
        end
      end
    end
  end
end

RspecTimeGuard.setup if defined?(RSpec)
