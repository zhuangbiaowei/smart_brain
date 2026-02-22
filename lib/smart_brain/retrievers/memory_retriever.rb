# frozen_string_literal: true

require_relative 'exact_retriever'
require_relative 'relational_retriever'

module SmartBrain
  module Retrievers
    class MemoryRetriever
      def initialize(config:)
        @config = config
        @exact = ExactRetriever.new
        @relational = RelationalRetriever.new(config: config)
      end

      def retrieve(query:, memory_items:, recent_turns:, entities:, refs:)
        limit = config.composition.fetch(:evidence_max_items, 12)
        exact_hits = exact.retrieve(query: query, memory_items: memory_items, recent_turns: recent_turns, limit: limit)
        relational_hits = relational.retrieve(query: query, entities: entities, refs: refs, limit: limit)

        (exact_hits + relational_hits)
          .sort_by { |h| -h.fetch(:score, 0.0) }
          .first(limit)
      end

      private

      attr_reader :config, :exact, :relational
    end
  end
end
