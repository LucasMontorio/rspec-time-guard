# frozen_string_literal: true

module RspecTimeGuard
  class Configuration
    attr_accessor :global_time_limit_seconds, :continue_on_timeout

    def initialize
      @global_time_limit_seconds = nil
      @continue_on_timeout = false
    end
  end
end
