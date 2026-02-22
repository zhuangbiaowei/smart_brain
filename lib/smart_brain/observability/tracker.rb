# frozen_string_literal: true

module SmartBrain
  module Observability
    class Tracker
      def initialize
        @compose_logs = []
        @commit_logs = []
      end

      def log_compose(payload)
        compose_logs << payload
      end

      def log_commit(payload)
        commit_logs << payload
      end

      def snapshot
        {
          compose_logs: compose_logs,
          commit_logs: commit_logs,
          metrics: {
            compose_p95_ms: p95(compose_logs.map { |l| l[:took_ms] }),
            memory_resource_ratio: memory_resource_ratio,
            token_over_budget_rate: token_over_budget_rate
          }
        }
      end

      private

      attr_reader :compose_logs, :commit_logs

      def p95(values)
        values = values.compact.sort
        return 0 if values.empty?

        index = [(values.length * 0.95).ceil - 1, 0].max
        values[index]
      end

      def memory_resource_ratio
        selected = compose_logs.flat_map { |l| l[:selected_evidence] || [] }
        return '0/0' if selected.empty?

        memory = selected.count { |e| e[:source] == 'memory' }
        resource = selected.count { |e| e[:source] == 'resource' }
        "#{memory}/#{resource}"
      end

      def token_over_budget_rate
        return 0.0 if compose_logs.empty?

        over = compose_logs.count { |l| l[:token_used].to_i > l[:token_limit].to_i }
        (over.to_f / compose_logs.length).round(3)
      end
    end
  end
end
