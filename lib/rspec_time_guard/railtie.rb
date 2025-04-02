# frozen_string_literal: true

module RspecTimeGuard
  class Railtie < Rails::Railtie
    initializer "rspec_time_guard.configure" do
      Rails.logger.info("INITIALIZER")

      config.after_initialize do
        Rails.logger.info("AFTER INITIALIZE")

        if defined?(RSpec) && Rails.env.test?
          require "rspec_time_guard"

          RspecTimeGuard.setup if defined?(RSpec)
        end
      end
    end
  end
end
