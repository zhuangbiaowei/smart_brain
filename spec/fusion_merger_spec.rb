# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SmartBrain::Fusion::Merger do
  it 'dedupes and keeps highest score for duplicate resource keys' do
    merger = described_class.new(config: SmartBrain::Configuration.load)

    result = merger.merge(
      query: 'x',
      memory_evidence: [],
      resource_evidence: [
        { id: 'a', source_uri: 'https://x', snippet: '1', score: 0.1, document_id: 'd1', section_id: 's1' },
        { id: 'b', source_uri: 'https://x', snippet: '2', score: 0.9, document_id: 'd1', section_id: 's1' }
      ]
    )

    expect(result[:selected].size).to eq(1)
    expect(result[:selected].first[:id]).to eq('b')
  end
end
