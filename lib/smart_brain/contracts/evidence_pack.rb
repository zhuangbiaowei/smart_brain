# frozen_string_literal: true

module SmartBrain
  module Contracts
    class EvidencePack
      REQUIRED_KEYS = %i[version request_id plan_id generated_at evidences].freeze

      def self.validate!(pack)
        missing = REQUIRED_KEYS.reject { |key| pack.key?(key) }
        raise ArgumentError, "invalid evidence pack: missing #{missing.join(', ')}" unless missing.empty?

        true
      end
    end
  end
end
