# frozen_string_literal: true

module RspecTimeGuard
  class Configuration
    attr_accessor :global_time_limit_seconds, :silent_mode

    def initialize
      @global_time_limit_seconds = nil
      @silent_mode = false
    end
  end
end
