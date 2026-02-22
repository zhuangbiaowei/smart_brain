# frozen_string_literal: true

require 'time'
require_relative 'smart_brain/configuration'
require_relative 'smart_brain/runtime'

module SmartBrain
  class << self
    attr_writer :runtime

    def configure(config_path: nil, smart_rag_client: nil, clock: -> { Time.now.utc })
      config = Configuration.load(config_path)
      @runtime = Runtime.build(config: config, smart_rag_client: smart_rag_client, clock: clock)
    end

    def commit_turn(session_id:, turn_events:)
      runtime.commit_turn(session_id: session_id, turn_events: turn_events)
    end

    def compose_context(session_id:, user_message:, agent_state: {})
      runtime.compose_context(session_id: session_id, user_message: user_message, agent_state: agent_state)
    end

    def diagnostics
      runtime.diagnostics
    end

    private

    def runtime
      @runtime ||= Runtime.build(config: Configuration.load, clock: -> { Time.now.utc })
    end
  end
end
