# frozen_string_literal: true

require 'securerandom'

module SmartBrain
  module MemoryStore
    class InMemory
      OVERWRITE_TYPES = %w[preferences goals tasks].freeze

      def initialize
        @by_session = Hash.new { |h, k| h[k] = [] }
        @entities_index = Hash.new { |h, k| h[k] = [] }
      end

      def upsert(extracted)
        session_id = extracted.fetch(:session_id)
        items = extracted.fetch(:items, [])
        written = []
        conflicts = []

        items.each do |item|
          existing = active_item(session_id: session_id, type: item[:type], key: item[:key])

          if existing && item[:status] == 'retracted'
            existing[:status] = 'retracted'
            conflicts << { type: 'retract', key: item[:key], previous_memory_item_id: existing[:id] }
            next
          end

          if existing && OVERWRITE_TYPES.include?(item[:type])
            existing[:status] = 'superseded'
            conflicts << { type: 'overwrite', key: item[:key], previous_memory_item_id: existing[:id] }
          end

          record = item.merge(id: SecureRandom.uuid, status: item[:status] || 'active')
          by_session[session_id] << record
          update_entities(session_id: session_id, record: record)
          written << record.slice(:id, :type, :key, :status, :confidence)
        end

        { count: written.size, items: written, conflicts: conflicts }
      end

      def active_items(session_id:)
        by_session[session_id].select { |item| item[:status] == 'active' }
      end

      def entities(session_id:)
        entities_index[session_id]
      end

      private

      attr_reader :by_session, :entities_index

      def active_item(session_id:, type:, key:)
        by_session[session_id].find { |row| row[:type] == type && row[:key] == key && row[:status] == 'active' }
      end

      def update_entities(session_id:, record:)
        return unless record[:type] == 'entities'

        value = record[:value_json]
        canonical = value[:canonical] || value[:name]
        existing = entities_index[session_id].find { |e| e[:canonical] == canonical && e[:kind] == value[:kind] }
        return if existing

        entities_index[session_id] << {
          id: SecureRandom.uuid,
          name: value[:name] || canonical,
          kind: value[:kind] || 'other',
          canonical: canonical,
          memory_item_id: record[:id]
        }
      end
    end
  end
end
