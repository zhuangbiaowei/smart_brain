# frozen_string_literal: true

require 'timeout'
require 'spec_helper'
require_relative '../lib/smart_brain/adapters/smart_rag/http_client'

RSpec.describe SmartBrain::Adapters::SmartRag::HttpClient do
  it 'maps successful response into evidence pack' do
    transport = lambda do |_plan, timeout_seconds:|
      expect(timeout_seconds).to eq(2)
      {
        plan_id: 'p1',
        supports_language_filter: true,
        evidences: [
          { id: 'e1', source_uri: 'https://a', snippet: 'x', score: 0.8, document_id: 'd1', section_id: 's1' }
        ]
      }
    end

    pack = described_class.new(transport: transport).retrieve(request_id: 'r1')
    expect(pack[:plan_id]).to eq('p1')
    expect(pack[:evidences].size).to eq(1)
  end

  it 'handles timeout with fallback warning' do
    transport = lambda do |_plan, timeout_seconds:|
      sleep(timeout_seconds + 0.1)
      raise Timeout::Error
    end

    pack = described_class.new(transport: transport, timeout_seconds: 0.01).retrieve(request_id: 'r2')
    expect(pack[:evidences]).to eq([])
    expect(pack[:warnings].join).to include('timeout')
  end

  it 'records ignored fields when backend lacks capability' do
    transport = lambda do |_plan, timeout_seconds:|
      {
        plan_id: 'p2',
        supports_language_filter: false,
        evidences: [],
        explain: { ignored_fields: ['diversity.by_source not supported'] }
      }
    end

    pack = described_class.new(transport: transport).retrieve(request_id: 'r3')
    expect(pack.dig(:explain, :ignored_fields)).to include('global_filters.language not supported')
    expect(pack.dig(:explain, :ignored_fields)).to include('diversity.by_source not supported')
  end
end
