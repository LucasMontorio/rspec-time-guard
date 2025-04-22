# frozen_string_literal: true

require "spec_helper"
require "rspec_time_guard"

RSpec.describe RspecTimeGuard do
  let(:test_rspec_config) { RSpec::Core::Configuration.new }

  before(:all) do
    # Store original RSpec configuration
    @original_config = RSpec.configuration.dup
  end

  after(:all) do
    # Restore original configuration after all tests
    RSpec.instance_variable_set(:@configuration, @original_config)
  end

  describe "configuration" do
    it "allows setting a global_time_limit_seconds option" do
      RspecTimeGuard.configure do |config|
        config.global_time_limit_seconds = 0.5
      end
      expect(RspecTimeGuard.configuration.global_time_limit_seconds).to eq(0.5)
    end

    it "allows setting the continue_on_timeout option" do
      RspecTimeGuard.configure do |config|
        config.continue_on_timeout = true
      end
      expect(RspecTimeGuard.configuration.continue_on_timeout).to eq(true)
    end
  end

  describe "setup" do
    before do
      allow(RSpec).to receive(:configure).and_yield(test_rspec_config)
    end

    it "adds an around hook to RSpec configuration" do
      expect(test_rspec_config).to receive(:around).with(:each)

      RspecTimeGuard.setup
    end
  end

  describe "time monitoring" do
    def run_with_time_guard(time_limit_seconds, continue_on_timeout: false, &example_block)
      # Setup configuration
      RspecTimeGuard.configure do |config|
        config.continue_on_timeout = continue_on_timeout
      end

      # Create example mock
      example = double("RSpec::Core::Example",
        object_id: rand(1000),
        metadata: {time_limit_seconds: time_limit_seconds},
        example_group: double(description: "example group"),
        description: "example description")

      # Track exception
      exception_set = nil
      allow(example).to receive(:exception=) { |error| exception_set = error }
      allow(example).to receive(:run) { example_block&.call }

      # Setup monitor and hook
      monitor = RspecTimeGuard::TimeoutMonitor.new
      allow(RspecTimeGuard).to receive(:monitor).and_return(monitor)

      test_thread = Thread.current
      monitor.register_test(example, time_limit_seconds, test_thread)

      allow(ObjectSpace).to receive(:_id2ref).and_return(test_thread)
      test_info = monitor.instance_variable_get(:@active_tests)[example.object_id]
      test_info[:start_time] = Time.now - time_limit_seconds - 0.1 if test_info

      # Run the test
      begin
        example.run

        # For tests with continue_on_timeout, we need to:
        # 1. Simulate a timeout condition
        # 2. Manually trigger the check to generate the warning
        if continue_on_timeout
          # Ensure the test appears to have timed out (same backdating we did earlier)
          test_info = monitor.instance_variable_get(:@active_tests)[example.object_id]
          test_info[:start_time] = Time.now - time_limit_seconds * 2 if test_info

          # Now trigger the timeout check to generate the warning
          monitor.send(:check_for_timeouts)
        end
      rescue RspecTimeGuard::TimeLimitExceededError => e
        example.exception = e
      ensure
        monitor.unregister_test(example)
      end

      exception_set
    end

    context "with per-example time limit" do
      it "allows examples within the time limit" do
        expect do
          run_with_time_guard(0.3) { sleep 0.1 }
        end.not_to raise_error
      end

      it "sets example.exception when example exceeds time limit" do
        exception = run_with_time_guard(0.1) { sleep 0.01 } # Short sleep, we simulate timeout
        expect(exception).to be_a(RspecTimeGuard::TimeLimitExceededError)
      end
    end

    context "with continue_on_timeout enabled" do
      it "outputs a warning but allows the example to complete" do
        expect do
          run_with_time_guard(0.1, continue_on_timeout: true) { sleep 0.2 }
        end.to output(/WARNING \[RSpecTimeGuard\]/).to_stderr
      end

      it "continues execution after timeout" do
        execution_completed = false

        expect do
          run_with_time_guard(0.1, continue_on_timeout: true) do
            sleep 0.2
            execution_completed = true
          end
        end.to output(/WARNING \[RSpecTimeGuard\]/).to_stderr

        expect(execution_completed).to be true
      end

      it "only outputs a warning once per example" do
        # Redirect stderr to count warnings
        original_stderr = $stderr
        $stderr = StringIO.new

        begin
          run_with_time_guard(0.1, continue_on_timeout: true) do
            sleep 0.3 # Sleep long enough to trigger multiple checks
          end

          warning_count = $stderr.string.scan("WARNING [RSpecTimeGuard]").count
        ensure
          $stderr = original_stderr
        end

        expect(warning_count).to eq(1)
      end
    end
  end

  describe "thread cleanup" do
    it "cleans up all monitoring threads after execution" do
      threads_before = Thread.list.map(&:object_id)

      RSpec.describe "SlowExample", :slow do
        it "runs a slow example" do
          sleep 0.3
        end
      end.run

      sleep 0.5

      threads_after = Thread.list.map(&:object_id)
      new_threads = threads_after - threads_before

      expect(new_threads.size).to be 0
    end

    it "only runs one monitoring thread at a time" do
      # Replace the actual implementation of start_monitor_thread
      monitor = RspecTimeGuard::TimeoutMonitor.new

      # Use a counter to track Thread.new calls
      thread_new_count = 0
      monitor_thread = double("MonitorThread", alive?: true)
      allow(monitor_thread).to receive(:[]=)

      # Mock Thread.new to return our test thread and count calls
      allow(Thread).to receive(:new) do
        thread_new_count += 1
        monitor_thread
      end

      # Add two test examples
      example1 = double("Example1", object_id: 123)
      example2 = double("Example2", object_id: 456)
      thread = double("Thread", object_id: 789)

      # Register both tests
      monitor.register_test(example1, 0.5, thread)
      monitor.register_test(example2, 0.5, thread)

      # Thread.new should only be called once
      expect(thread_new_count).to eq(1)
    end
  end

  describe "TimeoutMonitor" do
    let(:example) { double("RSpec::Core::Example", object_id: 123) }
    let(:thread) { Thread.current }
    let(:monitor) { RspecTimeGuard::TimeoutMonitor.new }

    describe "#register_test" do
      it "stores the test information with thread ID" do
        monitor.register_test(example, 0.5, thread)

        active_tests = monitor.instance_variable_get(:@active_tests)
        test_info = active_tests[example.object_id]

        expect(test_info[:example]).to eq(example)
        expect(test_info[:timeout]).to eq(0.5)
        expect(test_info[:thread_id]).to eq(thread.object_id)
        expect(test_info[:warned]).to eq(false)
        expect(test_info[:start_time]).to be_a(Time)
      end

      it "starts a monitor thread if none is running" do
        expect(Thread).to receive(:new).and_return(double("MonitorThread", :alive? => true, :[]= => nil))
        monitor.register_test(example, 0.5, thread)
      end

      it "doesn't start a new monitor thread if one is already running" do
        # First call starts the thread
        expect(Thread).to receive(:new).once.and_return(double("MonitorThread", :alive? => true, :[]= => nil))

        # Register two tests
        monitor.register_test(example, 0.5, thread)
        monitor.register_test(double("Example2", object_id: 456), 0.5, thread)
      end
    end

    describe "#unregister_test" do
      it "removes the test from active tests" do
        monitor.register_test(example, 0.5, thread)

        # Verify test was registered
        active_tests_before = monitor.instance_variable_get(:@active_tests)
        expect(active_tests_before).to have_key(example.object_id)

        # Unregister the test
        monitor.unregister_test(example)

        # Verify test was unregistered
        active_tests_after = monitor.instance_variable_get(:@active_tests)
        expect(active_tests_after).not_to have_key(example.object_id)
      end

      it "handles unregistering tests that were never registered" do
        expect { monitor.unregister_test(example) }.not_to raise_error
      end
    end
  end
end
