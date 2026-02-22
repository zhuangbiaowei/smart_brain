# frozen_string_literal: true

require 'securerandom'
require_relative 'contracts/retrieval_plan'
require_relative 'contracts/evidence_pack'
require_relative 'contracts/context_package'
require_relative 'observability/tracker'
require_relative 'event_store/in_memory'
require_relative 'memory_store/in_memory'
require_relative 'memory_extractor/extractor'
require_relative 'consolidator/working_summary'
require_relative 'retrieval_planner/planner'
require_relative 'retrievers/memory_retriever'
require_relative 'adapters/smart_rag/null_client'
require_relative 'fusion/merger'
require_relative 'context_composer/composer'

module SmartBrain
  class Runtime
    def self.build(config:, smart_rag_client: nil, clock:)
      event_store = EventStore::InMemory.new
      memory_store = MemoryStore::InMemory.new
      new(
        config: config,
        clock: clock,
        event_store: event_store,
        memory_store: memory_store,
        extractor: MemoryExtractor::Extractor.new(config: config),
        consolidator: Consolidator::WorkingSummary.new(config: config, clock: clock),
        planner: RetrievalPlanner::Planner.new(config: config),
        memory_retriever: Retrievers::MemoryRetriever.new(config: config),
        smart_rag_client: smart_rag_client || Adapters::SmartRag::NullClient.new,
        merger: Fusion::Merger.new(config: config),
        composer: ContextComposer::Composer.new(config: config, clock: clock),
        tracker: Observability::Tracker.new
      )
    end

    def initialize(config:, clock:, event_store:, memory_store:, extractor:, consolidator:, planner:, memory_retriever:, smart_rag_client:, merger:, composer:, tracker:)
      @config = config
      @clock = clock
      @event_store = event_store
      @memory_store = memory_store
      @extractor = extractor
      @consolidator = consolidator
      @planner = planner
      @memory_retriever = memory_retriever
      @smart_rag_client = smart_rag_client
      @merger = merger
      @composer = composer
      @tracker = tracker
    end

    def commit_turn(session_id:, turn_events:)
      started_at = monotonic_time
      now = clock.call
      turn = event_store.append_turn(session_id: session_id, turn_events: turn_events, created_at: now)
      entity_frequencies = event_store.entity_frequencies(
        session_id: session_id,
        window_turns: config.retention.dig(:entity_gate, :window_turns) || 20
      )

      extracted = extractor.extract(session_id: session_id, turn: turn, entity_frequencies: entity_frequencies)
      write_result = memory_store.upsert(extracted)
      turn_count = event_store.turns_count(session_id: session_id)
      recent_turns = event_store.recent_turns(session_id: session_id, limit: config.composition.fetch(:recent_turns_max, 8))
      stage_event = extracted[:items].any? { |item| item[:type] == 'decisions' || (item[:type] == 'tasks' && item.dig(:value_json, :status) == 'done') }
      summary = consolidator.update(
        session_id: session_id,
        turn_count: turn_count,
        recent_turns: recent_turns,
        memory_items: memory_store.active_items(session_id: session_id),
        stage_event: stage_event
      )

      result = {
        ok: true,
        commit_id: SecureRandom.uuid,
        session_id: session_id,
        turn_id: turn[:id],
        memory_written: write_result,
        summary: summary,
        explain: {
          retention: extracted.fetch(:explain, []),
          conflicts: write_result.fetch(:conflicts, []),
          summary: {
            triggered: summary[:triggered],
            reason: summary[:trigger_reason]
          }
        }
      }

      tracker.log_commit(
        commit_id: result[:commit_id],
        session_id: session_id,
        turn_id: turn[:id],
        memory_items: write_result[:items],
        conflicts: write_result[:conflicts],
        summary_triggered: summary[:triggered],
        summary_reason: summary[:trigger_reason],
        took_ms: elapsed_ms(started_at)
      )
      result
    end

    def compose_context(session_id:, user_message:, agent_state: {})
      started_at = monotonic_time
      recent_turns = event_store.recent_turns(session_id: session_id, limit: config.composition.fetch(:recent_turns_max, 8))
      refs = event_store.recent_refs(session_id: session_id, limit: config.composition.fetch(:recent_turns_max, 8))
      request_id = SecureRandom.uuid
      plan = planner.plan(
        request_id: request_id,
        session_id: session_id,
        user_message: user_message,
        agent_state: agent_state,
        recent_turns: recent_turns,
        refs: refs
      )
      Contracts::RetrievalPlan.validate!(plan)

      memory_evidence = memory_retriever.retrieve(
        query: user_message,
        memory_items: memory_store.active_items(session_id: session_id),
        recent_turns: recent_turns,
        entities: memory_store.entities(session_id: session_id),
        refs: refs
      )

      resource_pack = if plan.dig(:resource_retrieval, :enabled)
                        smart_rag_client.retrieve(plan)
                      else
                        {
                          version: '0.1',
                          request_id: request_id,
                          plan_id: "local-#{request_id}",
                          generated_at: clock.call.iso8601,
                          evidences: [],
                          explain: { ignored_fields: [] },
                          warnings: ['resource retrieval disabled by planner']
                        }
                      end

      Contracts::EvidencePack.validate!(resource_pack)
      merged_bundle = merger.merge(
        query: user_message,
        memory_evidence: memory_evidence,
        resource_evidence: resource_pack.fetch(:evidences, [])
      )
      merged_bundle[:ignored_fields] = Array(merged_bundle[:ignored_fields]) + Array(resource_pack.dig(:explain, :ignored_fields))

      context = composer.compose(
        session_id: session_id,
        user_message: user_message,
        plan: plan,
        plan_id: resource_pack[:plan_id],
        summary: consolidator.latest_summary(session_id),
        recent_turns: recent_turns,
        evidence_bundle: merged_bundle
      )
      Contracts::ContextPackage.validate!(context)

      took_ms = elapsed_ms(started_at)
      token_budget = context.dig(:constraints, :token_budget) || {}
      tracker.log_compose(
        context_id: context[:context_id],
        session_id: session_id,
        request_id: request_id,
        plan_id: resource_pack[:plan_id],
        selected_evidence: context[:evidence],
        ignored_fields: context.dig(:debug, :ignored),
        token_used: token_budget[:used_estimate] || 0,
        token_limit: token_budget[:limit] || config.composition.fetch(:token_limit, 8192),
        took_ms: took_ms
      )
      context
    end

    def diagnostics
      tracker.snapshot.merge(turns: event_store.all_turns(session_id: nil))
    end

    private

    attr_reader :config, :clock, :event_store, :memory_store, :extractor, :consolidator,
                :planner, :memory_retriever, :smart_rag_client, :merger, :composer, :tracker

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def elapsed_ms(start)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(2)
    end
  end
end
