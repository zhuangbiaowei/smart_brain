# frozen_string_literal: true

module SmartBrain
  module Contracts
    class RetrievalPlan
      REQUIRED_KEYS = %i[version request_id purpose queries budget].freeze

      def self.validate!(plan)
        missing = REQUIRED_KEYS.reject { |key| plan.key?(key) }
        raise ArgumentError, "invalid retrieval plan: missing #{missing.join(', ')}" unless missing.empty?
        raise ArgumentError, 'invalid retrieval plan: queries must not be empty' if Array(plan[:queries]).empty?

        true
      end
    end
  end
end
