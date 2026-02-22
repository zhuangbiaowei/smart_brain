# frozen_string_literal: true

module SmartBrain
  module Contracts
    class ContextPackage
      REQUIRED_KEYS = %i[version context_id session_id created_at user_message evidence].freeze

      def self.validate!(pkg)
        missing = REQUIRED_KEYS.reject { |key| pkg.key?(key) }
        raise ArgumentError, "invalid context package: missing #{missing.join(', ')}" unless missing.empty?

        true
      end
    end
  end
end
