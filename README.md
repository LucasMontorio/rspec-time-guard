[//]: # (TODO: Add a public TODO list?)

# ⚠️ **_This project is a Work In Progress_** ⚠️

# RspecTimeGuard

`RspecTimeGuard` helps you identify and manage slow-running tests in your RSpec test suite by setting time limits on individual examples or globally across your test suite.


## Installation

Add this line to your application's Gemfile:

```ruby
gem 'rspec-time-guard'
```

And then execute:

```bash
$ bundle install
```

Or install it globally:

```bash
$ gem install rspec-time-guard
```


## Usage

### Basic Setup

RSpec Time Guard integrates automatically with Rails applications in the test environment. For non-Rails projects, you'll need to manually require and set it up.

#### Rails Setup

The gem will automatically initialize itself when Rails loads in the test environment.

#### Manual Setup (for non-Rails projects)

In your `spec_helper.rb` or similar file:

```ruby
require 'rspec_time_guard'

RspecTimeGuard.setup
```

### Configuration

Create an initializer at `config/initializers/rspec_time_guard.rb` (for Rails) or add to your spec configuration file:

```ruby
RspecTimeGuard.configure do |config|
  # Set a global time limit in seconds for all examples (nil = no global limit)
  config.global_time_limit_seconds = 1.0

  # Whether to continue running tests that exceed their time limit
  # true = shows warning but allows test to complete
  # false = raises TimeLimitExceededError and stops the test (default)
  config.continue_on_timeout = false
end
```

### Setting Time Limits

#### Option 1: Global Time Limit

Set a global time limit that applies to all your tests through configuration:

```ruby
RspecTimeGuard.configure do |config|
  config.global_time_limit_seconds = 0.5 # 500 milliseconds
end
```

#### Option 2: Per-Example Time Limits

Add a specific time limit to individual examples using metadata:

```ruby
# Apply a 0.25 second time limit to this test
it "should do something quickly", time_limit_seconds: 0.25 do
  # Your test code
end

# Apply a 5 second time limit to this group of tests
describe "operations that need more time", time_limit_seconds: 5 do
  it "does a complex operation" do
    # ...
  end

  it "does another complex operation" do
    # ...
  end
end
```

### Error Handling

When a test exceeds its time limit:

1. If `continue_on_timeout` is `false` (default):
   - The test will be interrupted
   - A `RspecTimeGuard::TimeLimitExceededError` will be raised
   - The test will be marked as failed

2. If `continue_on_timeout` is `true`:
   - A warning message will be displayed
   - The test will continue running until completion
   - The test will pass or fail based on its assertions, not its timing

### Important Notes on Test Execution

#### Test Interruption

When a time limit is exceeded and `continue_on_timeout` is set to `false` (the default):

- Test execution is immediately interrupted at the time limit
- Any code after the point where the timeout occurs will not be executed
- Cleanup operations such as database transactions may not complete normally
- Any assertions or expectations after the timeout point won't be evaluated

This means if your test has important cleanup steps or assertions near the end, they might not run if the test times out earlier.
If you need to ensure all test code runs even when timing out, use the `continue_on_timeout` option.

#### Thread Safety Considerations

RSpec Time Guard uses threads for execution monitoring. While we take care to properly clean up these threads, be aware that:

1. Tests with threading or process-spawning code might behave unexpectedly
2. Thread-local variables could be lost when a test is interrupted
3. Some Ruby extensions and libraries might not be fully thread-safe
ite


## Examples

### Basic Example

```ruby
# spec/models/user_spec.rb
require 'rails_helper'

RSpec.describe User, type: :model do
  it "validates email quickly", time_limit_seconds: 0.1 do
    user = User.new(email: "invalid")
    expect(user.valid?).to be false
  end

  # This test will use the global time limit if configured
  it "can generate a profile" do
    user = User.create(name: "John", email: "john@example.com")
    expect(user.generate_profile).to include(name: "John")
  end
end
```


## How It Works

RSpec Time Guard works by:

1. Setting up an RSpec `around(:each)` hook
2. Running your test in a separate thread
3. Monitoring execution time
4. Taking action if the time limit is exceeded

### Performance Considerations
> ⚠️ **Note**: Setting a global time limit with `global_time_limit_seconds` creates a monitoring thread for each test in your suite. This may result in slightly reduced performance, especially in large test suites. For optimal performance, you might consider applying time limits only to specific tests that are prone to slowness rather than setting a global limit.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/rspec-time-guard. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/[USERNAME]/rspec-time-guard/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the `RspecTimeGuard` project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/rspec-time-guard/blob/main/CODE_OF_CONDUCT.md).
