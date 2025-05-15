# frozen_string_literal: true

module RspecTimeGuard
  class Railtie < Rails::Railtie
    initializer 'rspec_time_guard.configure' do
      config.after_initialize do
        if defined?(RSpec) && Rails.env.test?
          require 'rspec_time_guard'

          RspecTimeGuard.setup if defined?(RSpec)
        end
      end
    end
  end
end
