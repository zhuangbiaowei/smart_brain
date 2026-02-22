# frozen_string_literal: true

module SmartBrain
  module Fusion
    class Merger
      def initialize(config:)
        @config = config
      end

      def merge(query:, memory_evidence:, resource_evidence:)
        combined = (memory_evidence + normalize_resource(resource_evidence))
        deduped = dedupe(combined)
        ranked = deduped.sort_by { |item| -rerank_score(item, query) }
        diversified, dropped = apply_diversity(ranked)
        selected = apply_budget(diversified)

        {
          selected: selected,
          dropped: dropped,
          ignored_fields: []
        }
      end

      private

      attr_reader :config

      def normalize_resource(items)
        items.map do |item|
          item.merge(
            source: 'resource',
            score: item.fetch(:score, item.dig(:signals, :rerank_score) || item.dig(:signals, :rrf_score) || 0.4),
            ref: item[:ref] || {
              document_id: item[:document_id],
              section_id: item[:section_id],
              chunk_index: item.dig(:metadata, :chunk_index)
            }
          )
        end
      end

      def dedupe(items)
        deduped = {}
        items.each do |item|
          key = dedupe_key(item)
          existing = deduped[key]
          deduped[key] = item if existing.nil? || item.fetch(:score, 0.0) > existing.fetch(:score, 0.0)
        end
        deduped.values
      end

      def apply_diversity(items)
        by_document = config.composition.dig(:diversity, :by_document) || 3
        by_source = config.composition.dig(:diversity, :by_source_uri) || 2

        doc_counter = Hash.new(0)
        source_counter = Hash.new(0)
        kept = []
        dropped = []

        items.each do |item|
          ref = item[:ref] || {}
          document_key = ref[:document_id] || item[:title]
          source_prefix = item[:source_uri].to_s.split('/')[0, 3].join('/')
          source_key = source_prefix.empty? ? item[:source_uri] : source_prefix

          if doc_counter[document_key] >= by_document || source_counter[source_key] >= by_source
            dropped << item.merge(drop_reason: 'diversity')
            next
          end

          doc_counter[document_key] += 1
          source_counter[source_key] += 1
          kept << item
        end

        [kept, dropped]
      end

      def apply_budget(items)
        limit = config.composition.fetch(:evidence_max_items, 12)
        max_chars = config.composition.fetch(:max_snippet_chars, 800)
        ratio = parse_ratio(config.composition.dig(:diversity, :memory_resource_ratio) || '40/60')

        memory_limit = (limit * ratio[:memory]).floor
        resource_limit = limit - memory_limit
        selected = []

        memory_items = items.select { |i| i[:source] == 'memory' }.first(memory_limit)
        resource_items = items.select { |i| i[:source] == 'resource' }.first(resource_limit)
        selected.concat(memory_items).concat(resource_items)

        if selected.length < limit
          leftovers = (items - selected).first(limit - selected.length)
          selected.concat(leftovers)
        end

        selected.first(limit).map do |item|
          snippet = item[:snippet].to_s
          item.merge(snippet: snippet.length > max_chars ? "#{snippet[0...max_chars]}..." : snippet)
        end
      end

      def parse_ratio(text)
        memory, resource = text.to_s.split('/').map(&:to_i)
        total = memory + resource
        return { memory: 0.4, resource: 0.6 } if total <= 0

        { memory: memory.to_f / total, resource: resource.to_f / total }
      end

      def rerank_score(item, query)
        score = item.fetch(:score, 0.0)
        score + lexical_boost(item: item, query: query)
      end

      def lexical_boost(item:, query:)
        terms = query.to_s.downcase.scan(/[[:alnum:]_\-\p{Han}]+/)
        text = "#{item[:title]} #{item[:snippet]}".downcase
        terms.count { |term| text.include?(term) } * 0.05
      end

      def dedupe_key(item)
        ref = item[:ref] || {}
        if ref[:document_id] && ref[:section_id]
          "resource:#{ref[:document_id]}:#{ref[:section_id]}:#{ref[:chunk_index]}"
        elsif ref[:memory_item_id]
          "memory:#{ref[:memory_item_id]}"
        elsif ref[:turn_id] && ref[:message_id]
          "memory-turn:#{ref[:turn_id]}:#{ref[:message_id]}"
        else
          "fallback:#{item[:id]}"
        end
      end
    end
  end
end
