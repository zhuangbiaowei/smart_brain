# frozen_string_literal: true

module SmartBrain
  module MemoryExtractor
    class Extractor
      def initialize(config:)
        @config = config
      end

      def extract(session_id:, turn:, entity_frequencies: Hash.new(0))
        events = turn.fetch(:turn_events)
        explain = []
        items = []

        collect(items, explain, events[:tasks], type: 'tasks', confidence: confidence(:tool_derived), source_turn_id: turn[:id])
        collect(items, explain, events[:decisions], type: 'decisions', confidence: confidence(:user_asserted), source_turn_id: turn[:id])
        collect(items, explain, events[:goals], type: 'goals', confidence: confidence(:user_asserted), source_turn_id: turn[:id])
        collect(items, explain, events[:events], type: 'events', confidence: confidence(:tool_derived), source_turn_id: turn[:id])

        Array(events[:preferences]).each do |preference|
          key = preference.fetch(:key)
          if preference[:confirmed]
            items << build_item(type: 'preferences', key: key, value_json: preference, source_turn_id: turn[:id], confidence: confidence(:user_asserted))
            explain << "write preferences:#{key}"
          else
            explain << "skip preferences:#{key} not confirmed"
          end
        end

        Array(events[:entities]).each do |entity|
          key = entity.fetch(:key)
          canonical = (entity[:canonical] || entity[:name]).to_s.downcase
          should_write = entity[:remember] || entity_structure_signal?(entity) || entity_frequencies[canonical] >= freq_threshold
          if should_write
            items << build_item(type: 'entities', key: key, value_json: entity, source_turn_id: turn[:id], confidence: confidence(:inferred))
            explain << "write entities:#{key}"
          else
            explain << "skip entities:#{key} below threshold"
          end
        end

        Array(events[:retractions]).each do |retraction|
          items << build_item(type: retraction.fetch(:type), key: retraction.fetch(:key), value_json: retraction, source_turn_id: turn[:id], confidence: confidence(:user_asserted), status: 'retracted')
          explain << "retract #{retraction.fetch(:type)}:#{retraction.fetch(:key)}"
        end

        {
          session_id: session_id,
          items: items,
          explain: explain
        }
      end

      private

      attr_reader :config

      def collect(items, explain, raw_items, type:, confidence:, source_turn_id:)
        Array(raw_items).each do |entry|
          key = entry.fetch(:key)
          items << build_item(type: type, key: key, value_json: entry, source_turn_id: source_turn_id, confidence: confidence)
          explain << "write #{type}:#{key}"
        end
      end

      def build_item(type:, key:, value_json:, source_turn_id:, confidence:, status: 'active')
        {
          type: type,
          key: key,
          value_json: value_json,
          source_turn_id: source_turn_id,
          confidence: confidence,
          status: status,
          updated_at: Time.now.utc.iso8601
        }
      end

      def confidence(name)
        config.retention.fetch(:confidence, {}).fetch(name, 0.6)
      end

      def freq_threshold
        config.retention.dig(:entity_gate, :freq_threshold) || 2
      end

      def entity_structure_signal?(entity)
        canonical = entity[:canonical].to_s
        canonical.include?('/') || canonical.include?('http') || canonical.include?('.')
      end
    end
  end
end
