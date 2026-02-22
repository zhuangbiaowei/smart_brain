# frozen_string_literal: true

require 'securerandom'

module SmartBrain
  module EventStore
    class InMemory
      def initialize
        @sessions = {}
      end

      def append_turn(session_id:, turn_events:, created_at:)
        session = sessions[session_id] ||= { seq: 0, turns: [] }
        session[:seq] += 1
        turn_id = SecureRandom.uuid
        messages = normalize_messages(turn_id: turn_id, messages: turn_events[:messages] || [], created_at: created_at)
        refs = normalize_refs(turn_id: turn_id, refs: turn_events[:refs] || [], created_at: created_at)
        turn = {
          id: turn_id,
          session_id: session_id,
          seq: session[:seq],
          created_at: created_at.iso8601,
          turn_events: turn_events.merge(messages: messages, refs: refs)
        }
        session[:turns] << turn
        turn
      end

      def turns_count(session_id:)
        (sessions[session_id] || { turns: [] })[:turns].size
      end

      def recent_turns(session_id:, limit:)
        session = sessions[session_id]
        return [] unless session

        session[:turns].last(limit).flat_map do |turn|
          (turn.dig(:turn_events, :messages) || []).map do |m|
            {
              turn_id: turn[:id],
              message_id: m[:id],
              role: m[:role],
              content: m[:content],
              created_at: m[:created_at]
            }
          end
        end
      end

      def recent_refs(session_id:, limit:)
        session = sessions[session_id]
        return [] unless session

        session[:turns].last(limit).flat_map { |t| t.dig(:turn_events, :refs) || [] }
      end

      def entity_frequencies(session_id:, window_turns:)
        session = sessions[session_id]
        return Hash.new(0) unless session

        freq = Hash.new(0)
        session[:turns].last(window_turns).each do |turn|
          Array(turn.dig(:turn_events, :entities)).each do |entity|
            canonical = entity[:canonical] || entity[:name]
            freq[canonical.to_s.downcase] += 1
          end
        end
        freq
      end

      def all_turns(session_id:)
        return sessions.values.flat_map { |s| s[:turns] } if session_id.nil?

        (sessions[session_id] || { turns: [] })[:turns]
      end

      private

      attr_reader :sessions

      def normalize_messages(turn_id:, messages:, created_at:)
        messages.map do |m|
          m.merge(
            id: m[:id] || SecureRandom.uuid,
            turn_id: turn_id,
            created_at: m[:created_at] || created_at.iso8601
          )
        end
      end

      def normalize_refs(turn_id:, refs:, created_at:)
        refs.map do |ref|
          ref.merge(
            id: ref[:id] || SecureRandom.uuid,
            turn_id: turn_id,
            created_at: ref[:created_at] || created_at.iso8601,
            ref_meta_json: ref[:ref_meta_json] || {}
          )
        end
      end
    end
  end
end
