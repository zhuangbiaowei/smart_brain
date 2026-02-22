# frozen_string_literal: true

module SmartBrain
  module Consolidator
    class WorkingSummary
      def initialize(config:, clock:)
        @config = config
        @clock = clock
        @summaries = {}
        @last_summary_turn = Hash.new(0)
      end

      def update(session_id:, turn_count:, recent_turns:, memory_items:, stage_event: false)
        reason = trigger_reason(session_id: session_id, turn_count: turn_count, recent_turns: recent_turns, stage_event: stage_event)
        return latest_summary(session_id).merge(triggered: false, trigger_reason: 'not_triggered') unless reason

        summary = {
          summary_version: next_version(session_id),
          summary_source_turn_range: source_turn_range(turn_count),
          summary_generated_at: clock.call.iso8601,
          text: build_text(memory_items),
          triggered: true,
          trigger_reason: reason
        }
        summaries[session_id] = summary
        last_summary_turn[session_id] = turn_count
        summary
      end

      def latest_summary(session_id)
        summaries[session_id] || default_summary
      end

      private

      attr_reader :config, :clock, :summaries, :last_summary_turn

      def trigger_reason(session_id:, turn_count:, recent_turns:, stage_event:)
        turns_since_last = turn_count - last_summary_turn[session_id]
        threshold = config.retention.fetch(:summarize_after_turns, 12)
        return 'turn_threshold' if turns_since_last >= threshold

        token_limit = config.composition.fetch(:token_limit, 8192)
        token_used = estimate_tokens(recent_turns)
        return 'token_pressure' if token_used > (token_limit * 0.7)
        return 'stage_event' if stage_event

        nil
      end

      def estimate_tokens(recent_turns)
        recent_turns.sum { |t| t[:content].to_s.length / 4 }
      end

      def next_version(session_id)
        previous = summaries[session_id]
        previous ? previous[:summary_version] + 1 : 1
      end

      def source_turn_range(turn_count)
        { from: [turn_count - (config.retention.fetch(:summarize_after_turns, 12) - 1), 1].max, to: turn_count }
      end

      def build_text(memory_items)
        goals = memory_items.select { |i| i[:type] == 'goals' }
        tasks = memory_items.select { |i| i[:type] == 'tasks' }
        decisions = memory_items.select { |i| i[:type] == 'decisions' }
        refs = memory_items.select { |i| i[:type] == 'entities' }

        [
          'Goals:',
          *to_lines(goals, fallback: '- None'),
          'Decisions:',
          *to_lines(decisions, fallback: '- None'),
          'Tasks:',
          *to_lines(tasks, fallback: '- None'),
          'Key References:',
          *to_lines(refs, fallback: '- None'),
          'Open Questions:',
          '- None'
        ].join("\n")
      end

      def to_lines(items, fallback:)
        return [fallback] if items.empty?

        items.first(5).map { |i| "- #{i[:key]}" }
      end

      def default_summary
        {
          summary_version: 0,
          summary_source_turn_range: { from: 0, to: 0 },
          summary_generated_at: clock.call.iso8601,
          text: "Goals:\n- None\nDecisions:\n- None\nTasks:\n- None\nKey References:\n- None\nOpen Questions:\n- None",
          triggered: false,
          trigger_reason: 'empty'
        }
      end
    end
  end
end
