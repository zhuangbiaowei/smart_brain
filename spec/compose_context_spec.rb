# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'SmartBrain.compose_context' do
  it 'returns context package with trace ids and slots' do
    SmartBrain.configure

    SmartBrain.commit_turn(
      session_id: 's1',
      turn_events: {
        messages: [
          { role: 'user', content: '请继续 SmartBrain 设计' },
          { role: 'assistant', content: '好的' }
        ],
        tasks: [{ key: 'task:smartbrain:m1', title: 'M1 chain', status: 'doing' }]
      }
    )

    context = SmartBrain.compose_context(
      session_id: 's1',
      user_message: '继续 SmartBrain 设计并给出引用',
      agent_state: { mode: 'coding' }
    )

    expect(context[:version]).to eq('0.1')
    expect(context[:session_id]).to eq('s1')
    expect(context[:user_message]).to eq(role: 'user', content: '继续 SmartBrain 设计并给出引用')
    expect(context).to have_key(:recent_turns)
    expect(context).to have_key(:evidence)
    expect(context).to have_key(:constraints)
    expect(context.dig(:debug, :trace, :context_id)).not_to be_nil
    expect(context.dig(:debug, :trace, :request_id)).not_to be_nil
    expect(context.dig(:debug, :trace, :plan_id)).not_to be_nil
  end

  it 'applies evidence truncation and diversity constraints' do
    SmartBrain.configure

    3.times do |i|
      SmartBrain.commit_turn(
        session_id: 's2',
        turn_events: {
          messages: [{ role: 'user', content: "repo smart_rag doc #{i}" }],
          entities: [{ key: "entity:repo:smart_rag_#{i}", kind: 'repo', canonical: 'smart_rag', name: 'smart_rag', remember: true }],
          refs: [{ ref_type: 'url', ref_uri: 'https://example.com/a/b/c', ref_meta_json: { n: i } }]
        }
      )
    end

    context = SmartBrain.compose_context(session_id: 's2', user_message: 'smart_rag 引用 最近 文档')

    expect(context[:evidence].size).to be <= 12
    expect(context[:evidence].all? { |e| e[:snippet].to_s.length <= 803 }).to eq(true)
    expect(context.dig(:constraints, :diversity, :by_document)).to eq(3)
  end
end
