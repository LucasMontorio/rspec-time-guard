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
    # For direct testing of the hook's behavior, we need to simulate it
    def run_with_time_guard(time_limit_seconds, continue_on_timeout: false, &example_block)
      RspecTimeGuard.configure do |config|
        config.continue_on_timeout = continue_on_timeout
      end

      example = double("RSpec::Core::Example")
      allow(example).to receive(:metadata).and_return(time_limit_seconds: time_limit_seconds)
      allow(example).to receive(:run) do
        # Run the provided block as if it were the example
        example_block&.call
      end

      # Extract the around hook from our setup
      hook_block = nil
      expect(test_rspec_config).to receive(:around) do |_scope, &block|
        hook_block = block
      end

      # Setup with test config
      allow(RSpec).to receive(:configure).and_yield(test_rspec_config)
      RspecTimeGuard.setup

      # Execute the hook directly with our mock example
      hook_block.call(example)
    end

    context "with per-example time limit" do
      it "allows examples within the time limit" do
        expect do
          run_with_time_guard(0.3) { sleep 0.1 }
        end.not_to raise_error
      end

      it "raises an error when example exceeds time limit" do
        expect do
          run_with_time_guard(0.1) { sleep 0.2 }
        end.to raise_error(RspecTimeGuard::TimeLimitExceededError)
      end
    end

    context "with continue_on_timeout enabled" do
      it "outputs a warning but allows the example to complete" do
        expect do
          run_with_time_guard(0.1, continue_on_timeout: true) { sleep 0.2 }
        end.to output(/Example exceeded timeout/).to_stderr
      end

      it "continues execution after timeout" do
        execution_completed = false

        expect do
          run_with_time_guard(0.1, continue_on_timeout: true) do
            sleep 0.2
            execution_completed = true
          end
        end.to output(/Example exceeded timeout/).to_stderr

        expect(execution_completed).to be true
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
  end
end
