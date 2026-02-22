# frozen_string_literal: true

module SmartBrain
  module Retrievers
    class ExactRetriever
      def retrieve(query:, memory_items:, recent_turns:, limit:)
        terms = tokenize(query)

        memory_hits = memory_items.filter_map do |item|
          haystack = "#{item[:key]} #{item[:value_json]}".downcase
          score = overlap_score(terms, haystack)
          next if score <= 0

          {
            id: item[:id],
            source: 'memory',
            source_uri: "smartbrain://memory/#{item[:id]}",
            title: item[:key],
            snippet: item[:value_json].to_s,
            mode: 'exact',
            score: score + (item[:confidence] || 0.5),
            ref: { memory_item_id: item[:id] }
          }
        end

        turn_hits = recent_turns.filter_map.with_index do |turn, idx|
          haystack = turn[:content].to_s.downcase
          score = overlap_score(terms, haystack)
          next if score <= 0

          {
            id: "turn-#{idx}",
            source: 'memory',
            source_uri: 'smartbrain://recent_turn',
            title: 'Recent Turn',
            snippet: turn[:content].to_s,
            mode: 'exact',
            score: score,
            ref: { turn_id: turn[:turn_id], message_id: turn[:message_id] }
          }
        end

        (memory_hits + turn_hits).sort_by { |h| -h[:score] }.first(limit)
      end

      private

      def tokenize(text)
        text.to_s.downcase.scan(/[[:alnum:]_\-\p{Han}]+/).uniq
      end

      def overlap_score(terms, haystack)
        return 0.0 if terms.empty?

        hits = terms.count { |t| haystack.include?(t) }
        return 0.0 if hits.zero?

        hits.to_f / terms.length
      end
    end
  end
end
