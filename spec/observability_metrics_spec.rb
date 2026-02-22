# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Observability metrics' do
  it 'collects compose p95 and token over-budget rate' do
    SmartBrain.configure

    SmartBrain.commit_turn(
      session_id: 'm1',
      turn_events: {
        messages: [{ role: 'user', content: 'x' * 200 }],
        tasks: [{ key: 'task:m1:1', status: 'doing' }]
      }
    )

    3.times { SmartBrain.compose_context(session_id: 'm1', user_message: 'x references') }

    snapshot = SmartBrain.diagnostics
    metrics = snapshot[:metrics]

    expect(metrics[:compose_p95_ms]).to be >= 0
    expect(metrics[:memory_resource_ratio]).to match(%r{\d+/\d+})
    expect(metrics[:token_over_budget_rate]).to be >= 0.0
  end
end
