# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Context regression' do
  it 'keeps stable package shape for fixed session input' do
    SmartBrain.configure

    SmartBrain.commit_turn(
      session_id: 'reg',
      turn_events: {
        messages: [{ role: 'user', content: 'SmartBrain roadmap and refs' }],
        tasks: [{ key: 'task:reg:1', title: 'Roadmap', status: 'doing' }],
        decisions: [{ key: 'decision:reg:1', decision: 'Use contracts' }],
        entities: [{ key: 'entity:repo:smart_brain', kind: 'repo', canonical: 'smart_brain', name: 'smart_brain', remember: true }]
      }
    )

    context = SmartBrain.compose_context(session_id: 'reg', user_message: '请给 roadmap 的引用')

    expect(context.keys).to include(:version, :context_id, :session_id, :created_at, :working_summary, :evidence, :user_message, :constraints, :debug)
    expect(context.dig(:debug, :planner, :purpose)).to eq('research')
  end
end
