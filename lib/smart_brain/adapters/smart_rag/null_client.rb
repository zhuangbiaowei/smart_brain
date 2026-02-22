# frozen_string_literal: true

module SmartBrain
  module Adapters
    module SmartRag
      class NullClient
        def retrieve(plan)
          {
            version: '0.1',
            plan_id: "local-#{plan[:request_id]}",
            request_id: plan[:request_id],
            generated_at: Time.now.utc.iso8601,
            evidences: [],
            stats: { candidates: 0, returned: 0, took_ms: 0 },
            explain: { ignored_fields: [] },
            warnings: ['smart_rag client not configured; returned empty evidences']
          }
        end
      end
    end
  end
end
