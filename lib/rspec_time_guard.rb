# frozen_string_literal: true

require "rspec_time_guard/configuration"
require "rspec_time_guard/version"
require "rspec_time_guard/railtie" if defined?(Rails)

module RspecTimeGuard
  class TimeLimitExceededError < StandardError; end

  class TimeoutMonitor
    def initialize
      @active_tests = {}
      @mutex = Mutex.new
      @monitor_thread = nil
    end

    def register_test(example, timeout, thread)
      @mutex.synchronize do
        @active_tests[example.object_id] = {
          example: example,
          start_time: Time.now,
          timeout: timeout,
          thread_id: thread.object_id,
          warned: false
        }

        # NOTE: We start monitor thread if not already running
        start_monitor_thread if @monitor_thread.nil? || !@monitor_thread.alive?
      end
    end

    def unregister_test(example)
      @mutex.synchronize do
        @active_tests.delete(example.object_id)
      end
    end

    private

    def start_monitor_thread
      @monitor_thread = Thread.new do
        Thread.current[:name] = "rspec_time_guard_monitor"

        loop do
          check_for_timeouts
          sleep 0.5 # Check every half second, adjust as needed

          # Exit thread if no more tests to monitor
          break if @mutex.synchronize { @active_tests.empty? }
        end
      end
    end

    def check_for_timeouts
      now = Time.now
      timed_out_examples = []

      @mutex.synchronize do
        @active_tests.each do |_, info|
          elapsed = now - info[:start_time]
          timed_out_examples << info[:example] if elapsed > info[:timeout]
        end
      end

      # NOTE: We handle timeouts outside the mutex to avoid deadlocks
      timed_out_examples.each do |example|
        group_name = example.example_group.description
        test_name = example.description
        timeout = @active_tests[example.object_id][:timeout]
        elapsed = now - @active_tests[example.object_id][:start_time]
        thread = begin
          ObjectSpace._id2ref(@active_tests[example.object_id][:thread_id])
        rescue
          nil
        end

        next unless thread.alive?

        # NOTE: We create an error for RSpec to report
        error = TimeLimitExceededError.new("Test '#{group_name} #{test_name}' timed out after #{timeout}s (took #{elapsed.round(2)}s)")
        error.set_backtrace(thread.backtrace || [])

        if RspecTimeGuard.configuration.continue_on_timeout
          next if @active_tests[example.object_id][:warned]

          warn "WARNING [RSpecTimeGuard] - #{error.message}"

          @active_tests[example.object_id][:warned] = true
        else
          # NOTE: We use Thread.raise which is safer than Thread.kill
          # This allows the thread to clean up properly
          thread.raise(error)
        end
      end
    end
  end

  class << self
    def configure
      yield(configuration)
    end

    def configuration
      @_configuration ||= RspecTimeGuard::Configuration.new
    end

    def monitor
      @_monitor ||= TimeoutMonitor.new
    end

    def setup
      RSpec.configure do |config|
        config.around(:each) do |example|
          time_limit_seconds = example.metadata[:time_limit_seconds] || RspecTimeGuard.configuration.global_time_limit_seconds

          next example.run unless time_limit_seconds

          RspecTimeGuard.monitor.register_test(example, time_limit_seconds, Thread.current)

          begin
            example.run
          rescue RspecTimeGuard::TimeLimitExceededError => e
            # NOTE: This changes the example's status to failed and records our error
            example.exception = e
          ensure
            RspecTimeGuard.monitor.unregister_test(example)
          end
        end
      end
    end
  end
end
