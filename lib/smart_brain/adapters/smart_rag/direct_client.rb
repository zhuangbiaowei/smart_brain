# frozen_string_literal: true

module SmartBrain
  module Adapters
    module SmartRag
      class DirectClient
        def initialize(rag:)
          @rag = rag
        end

        def retrieve(plan)
          response = rag.retrieve(plan: plan)
          normalize_pack(response, request_id: plan[:request_id])
        rescue StandardError => e
          {
            version: '0.1',
            request_id: plan[:request_id],
            plan_id: "direct-error-#{plan[:request_id]}",
            generated_at: Time.now.utc.iso8601,
            evidences: [],
            stats: { candidates: 0, returned: 0, took_ms: 0 },
            explain: { ignored_fields: [] },
            warnings: ["smart_rag direct retrieve failed: #{e.message}"]
          }
        end

        private

        attr_reader :rag

        def normalize_pack(response, request_id:)
          pack = response.is_a?(Hash) ? response : {}
          {
            version: pack[:version] || '0.1',
            request_id: pack[:request_id] || request_id,
            plan_id: pack[:plan_id] || "direct-#{request_id}",
            generated_at: pack[:generated_at] || Time.now.utc.iso8601,
            evidences: Array(pack[:evidences]),
            stats: pack[:stats] || { candidates: Array(pack[:evidences]).size, returned: Array(pack[:evidences]).size, took_ms: 0 },
            explain: pack[:explain] || { ignored_fields: [] },
            warnings: Array(pack[:warnings])
          }
        end
      end
    end
  end
end
