# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'SmartBrain.commit_turn' do
  it 'writes gated memory items and applies confidence policy' do
    SmartBrain.configure

    result = SmartBrain.commit_turn(
      session_id: 's1',
      turn_events: {
        messages: [{ role: 'user', content: 'remember this' }],
        tasks: [{ key: 'task:smartbrain:bootstrap', title: 'Bootstrap SmartBrain', status: 'todo' }],
        decisions: [{ key: 'decision:smartbrain:storage', decision: 'Use Postgres by default' }],
        preferences: [
          { key: 'pref:writing:tone', value: 'focused and exacting', confirmed: true },
          { key: 'pref:tools:editor', value: 'vim', confirmed: false }
        ]
      }
    )

    expect(result[:ok]).to eq(true)
    expect(result[:memory_written][:count]).to eq(3)
    expect(result[:memory_written][:items].map { |i| i[:confidence] }).to include(0.8, 0.9)
    expect(result[:explain][:retention]).to include('skip preferences:pref:tools:editor not confirmed')
  end

  it 'supports overwrite conflict and retraction' do
    SmartBrain.configure

    SmartBrain.commit_turn(
      session_id: 's2',
      turn_events: {
        messages: [{ role: 'user', content: 'pref 1' }],
        preferences: [{ key: 'pref:writing:tone', value: 'concise', confirmed: true }]
      }
    )

    overwrite = SmartBrain.commit_turn(
      session_id: 's2',
      turn_events: {
        messages: [{ role: 'user', content: 'update pref' }],
        preferences: [{ key: 'pref:writing:tone', value: 'detailed', confirmed: true }]
      }
    )

    expect(overwrite[:explain][:conflicts].map { |c| c[:type] }).to include('overwrite')

    retract = SmartBrain.commit_turn(
      session_id: 's2',
      turn_events: {
        messages: [{ role: 'user', content: 'that is wrong' }],
        retractions: [{ type: 'preferences', key: 'pref:writing:tone', reason: 'wrong' }]
      }
    )

    expect(retract[:explain][:retention]).to include('retract preferences:pref:writing:tone')
  end

  it 'triggers summary by stage event' do
    SmartBrain.configure

    result = SmartBrain.commit_turn(
      session_id: 's3',
      turn_events: {
        messages: [{ role: 'user', content: 'task done' }],
        tasks: [{ key: 'task:smartbrain:m1', title: 'M1', status: 'done' }]
      }
    )

    expect(result.dig(:explain, :summary, :triggered)).to eq(true)
    expect(result.dig(:summary, :trigger_reason)).to eq('stage_event')
  end
end
