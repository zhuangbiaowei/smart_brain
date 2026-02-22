# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SmartBrain::RetrievalPlanner::Planner do
  it 'enables resource retrieval when user asks for references' do
    config = SmartBrain::Configuration.load
    planner = described_class.new(config: config)

    plan = planner.plan(
      request_id: 'r1',
      session_id: 's1',
      user_message: '请查资料并给引用',
      agent_state: {},
      recent_turns: [],
      refs: []
    )

    expect(plan.dig(:resource_retrieval, :enabled)).to eq(true)
    expect(plan[:queries].size).to be >= 1
    expect(plan.dig(:budget, :top_k)).to eq(30)
  end
end
