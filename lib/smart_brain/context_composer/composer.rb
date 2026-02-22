# frozen_string_literal: true

require 'securerandom'

module SmartBrain
  module ContextComposer
    class Composer
      def initialize(config:, clock:)
        @config = config
        @clock = clock
      end

      def compose(session_id:, user_message:, plan:, plan_id:, summary:, recent_turns:, evidence_bundle:)
        context_id = SecureRandom.uuid
        evidence = evidence_bundle.fetch(:selected, [])
        used_estimate = estimate_tokens(summary: summary[:text], recent_turns: recent_turns, evidence: evidence, user_message: user_message)
        token_limit = config.composition.fetch(:token_limit, 8192)

        {
          version: '0.1',
          context_id: context_id,
          session_id: session_id,
          created_at: clock.call.iso8601,
          system_blocks: [],
          developer_blocks: [],
          working_summary: summary[:text],
          recent_turns: recent_turns.first(config.composition.fetch(:recent_turns_max, 8)),
          evidence: evidence,
          user_message: { role: 'user', content: user_message },
          constraints: {
            token_budget: {
              limit: token_limit,
              used_estimate: used_estimate
            },
            diversity: {
              by_document: config.composition.dig(:diversity, :by_document) || 3,
              by_source: config.composition.dig(:diversity, :by_source_uri) || 2
            },
            truncation: {
              snippets_max_chars: config.composition.fetch(:max_snippet_chars, 800),
              recent_turns_max: config.composition.fetch(:recent_turns_max, 8)
            }
          },
          debug: {
            trace: {
              context_id: context_id,
              request_id: plan[:request_id],
              plan_id: plan_id
            },
            planner: {
              request_id: plan[:request_id],
              purpose: plan[:purpose],
              queries: plan[:queries].map { |q| q[:text] }
            },
            why_selected: evidence.map { |e| "#{e[:id]} score=#{e[:score]} source=#{e[:source]}" },
            ignored: evidence_bundle[:ignored_fields] || [],
            dropped: (evidence_bundle[:dropped] || []).map { |e| { id: e[:id], reason: e[:drop_reason] } }
          }
        }
      end

      private

      attr_reader :config, :clock

      def estimate_tokens(summary:, recent_turns:, evidence:, user_message:)
        text_size = summary.to_s.length
        text_size += recent_turns.sum { |t| t[:content].to_s.length }
        text_size += evidence.sum { |e| e[:snippet].to_s.length }
        text_size += user_message.to_s.length
        (text_size / 4.0).ceil
      end
    end
  end
end
