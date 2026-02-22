# frozen_string_literal: true

module SmartBrain
  module Retrievers
    class RelationalRetriever
      def initialize(config:)
        @config = config
      end

      def retrieve(query:, entities:, refs:, limit:)
        terms = query.to_s.downcase.scan(/[[:alnum:]_\-\p{Han}]+/)
        entity_hits = entities.filter_map do |entity|
          score = terms.count { |t| entity[:canonical].to_s.downcase.include?(t) || entity[:name].to_s.downcase.include?(t) }
          next if score.zero?

          {
            id: "entity-#{entity[:id]}",
            source: 'memory',
            source_uri: "smartbrain://entity/#{entity[:id]}",
            title: entity[:name],
            snippet: "Entity #{entity[:kind]}: #{entity[:canonical]}",
            mode: 'relational',
            score: score.to_f,
            ref: { memory_item_id: entity[:memory_item_id] }
          }
        end

        ref_hits = refs.filter_map do |ref|
          value = ref[:ref_uri].to_s.downcase
          score = terms.count { |t| value.include?(t) }
          next if score.zero?

          {
            id: "ref-#{ref[:id]}",
            source: 'memory',
            source_uri: ref[:ref_uri],
            title: ref[:ref_type],
            snippet: ref[:ref_meta_json].to_s,
            mode: 'relational',
            score: (score * 0.8).to_f,
            ref: { turn_id: ref[:turn_id] }
          }
        end

        (entity_hits + ref_hits).sort_by { |h| -h[:score] }.first(limit)
      end

      private

      attr_reader :config
    end
  end
end
