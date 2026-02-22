# frozen_string_literal: true

module SmartBrain
  module Adapters
    module SmartRag
      class HttpClient
        def initialize(transport:, timeout_seconds: 2)
          @transport = transport
          @timeout_seconds = timeout_seconds
        end

        def retrieve(plan)
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          raw = transport.call(plan, timeout_seconds: timeout_seconds)
          build_pack(raw: raw, request_id: plan[:request_id], took_ms: elapsed_ms(started_at))
        rescue Timeout::Error
          {
            version: '0.1',
            request_id: plan[:request_id],
            plan_id: "timeout-#{plan[:request_id]}",
            generated_at: Time.now.utc.iso8601,
            evidences: [],
            stats: { candidates: 0, returned: 0, took_ms: elapsed_ms(started_at) },
            explain: { ignored_fields: [] },
            warnings: ['smart_rag timeout; fallback to memory-only evidence']
          }
        end

        private

        attr_reader :transport, :timeout_seconds

        def build_pack(raw:, request_id:, took_ms:)
          ignored = []
          ignored << 'global_filters.language not supported' unless raw.key?(:supports_language_filter) && raw[:supports_language_filter]

          {
            version: '0.1',
            request_id: request_id,
            plan_id: raw[:plan_id] || "remote-#{request_id}",
            generated_at: Time.now.utc.iso8601,
            evidences: Array(raw[:evidences]),
            stats: {
              candidates: raw.dig(:stats, :candidates) || Array(raw[:evidences]).size,
              returned: Array(raw[:evidences]).size,
              took_ms: took_ms
            },
            explain: {
              ignored_fields: ignored + Array(raw.dig(:explain, :ignored_fields))
            },
            warnings: Array(raw[:warnings])
          }
        end

        def elapsed_ms(start)
          ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(2)
        end
      end
    end
  end
end
