# frozen_string_literal: true

module SmartBrain
  module RetrievalPlanner
    class Planner
      RESOURCE_HINTS = ['查资料', '引用', 'reference', 'research', '标准', '论文', '文档', 'compare', '对比', '来源'].freeze

      def initialize(config:)
        @config = config
      end

      def plan(request_id:, session_id:, user_message:, agent_state:, recent_turns:, refs:)
        queries = build_queries(user_message)
        plan = {
          version: '0.1',
          request_id: request_id,
          purpose: infer_purpose(user_message),
          queries: queries,
          global_filters: {},
          budget: {
            top_k: config.retrieval.fetch(:top_k, 30),
            candidate_k: config.retrieval.fetch(:candidate_k, 200),
            per_mode_k: {
              exact: 10,
              semantic: 10,
              hybrid: config.retrieval.fetch(:top_k, 30),
              relational: 10,
              associative: 8
            },
            diversity: {
              by_document: config.composition.dig(:diversity, :by_document) || 3,
              by_source: config.composition.dig(:diversity, :by_source_uri) || 2
            }
          },
          output: {
            include_snippets: true,
            max_snippet_chars: config.composition.fetch(:max_snippet_chars, 800)
          },
          resource_retrieval: {
            enabled: resource_retrieval_enabled?(user_message: user_message, recent_turns: recent_turns, refs: refs),
            reason: resource_reason(user_message: user_message, refs: refs)
          },
          debug: {
            trace: config.observability.fetch(:trace, true),
            caller: { app: 'smart_brain', session_id: session_id },
            recent_turns_count: recent_turns.size,
            agent_state: agent_state,
            ignored_fields: []
          }
        }

        attach_filter_hints!(plan: plan, user_message: user_message)
        plan
      end

      private

      attr_reader :config

      def build_queries(user_message)
        queries = [{ text: user_message, mode: 'hybrid', weight: 1.0, filters: {}, hints: {} }]
        return queries unless config.retrieval.dig(:query_expansion, :enabled)

        max = config.retrieval.dig(:query_expansion, :max_queries) || 8
        expansions = expansion_terms(user_message).first([max - 1, 0].max)
        queries.concat(expansions.map.with_index do |text, idx|
          { text: text, mode: 'associative', weight: 0.8 - (idx * 0.05), filters: {}, hints: { expanded: true } }
        end)
        queries
      end

      def expansion_terms(user_message)
        tokens = user_message.to_s.scan(/[[:alnum:]_\-\p{Han}]+/).uniq
        return [] if tokens.size < 2

        phrases = []
        phrases << tokens.first(3).join(' ')
        phrases << tokens.last(3).join(' ')
        phrases << tokens.sort.join(' ')
        phrases.uniq.reject { |p| p == user_message }
      end

      def infer_purpose(user_message)
        lowered = user_message.downcase
        return 'research' if RESOURCE_HINTS.any? { |hint| lowered.include?(hint) }

        'qa'
      end

      def resource_retrieval_enabled?(user_message:, recent_turns:, refs:)
        mode = config.retrieval.fetch(:enable_resource_retrieval, 'auto')
        return true if mode == true
        return false if mode == false

        lowered = user_message.downcase
        return true if RESOURCE_HINTS.any? { |hint| lowered.include?(hint) }
        return true if refs.any?

        recent_turns.any? { |turn| turn[:content].to_s.match?(%r{https?://|\.(md|rb|txt)}) }
      end

      def resource_reason(user_message:, refs:)
        lowered = user_message.downcase
        return 'user_requested_external_evidence' if RESOURCE_HINTS.any? { |hint| lowered.include?(hint) }
        return 'has_recent_refs' if refs.any?

        'auto_disabled_or_not_needed'
      end

      def attach_filter_hints!(plan:, user_message:)
        text = user_message.downcase
        if text.include?('最近') || text.include?('recent')
          plan[:global_filters][:time_range] = { from: (Time.now.utc - 7 * 24 * 3600).iso8601, to: Time.now.utc.iso8601 }
        end

        if text.include?('smart_rag')
          plan[:global_filters][:source_uri_prefix] = ['smart_rag']
        end
      end
    end
  end
end
