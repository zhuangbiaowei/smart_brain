# frozen_string_literal: true

require 'logger'
require 'json'

# Follow smart_agent/test.rb style: load SmartPrompt first, then SmartAgent.
require 'smart_prompt'
require 'smart_agent'
require_relative 'lib/smart_brain'
require_relative 'lib/smart_brain/adapters/smart_rag/direct_client'

begin
  require '/home/mlf/smart_ai/smart_rag/lib/smart_rag'
rescue LoadError => e
  warn "SmartRAG load failed: #{e.message}"
  warn 'Please install SmartRAG dependencies (especially sequel/pg) before running this example.'
  exit 1
end

rag_config = SmartRAG::Config.load('/home/mlf/smart_ai/smart_rag/config/smart_rag.yml')
# SmartRAG config may include database.extensions with pgvector.
# For Sequel, pgvector should be loaded globally via Sequel.extension.
db_cfg = (rag_config[:database] || {}).dup
db_exts = Array(db_cfg.delete(:extensions)).map(&:to_s)
if db_exts.include?('pgvector')
  require 'sequel'
  Sequel.extension 'pgvector'
end
# SmartRAG currently passes database config into EmbeddingService.
# Inject SmartPrompt config path here so EmbeddingService can boot correctly.
db_cfg[:config_path] = File.expand_path('./config/example_llm.yml', __dir__)
rag_config = rag_config.merge(database: db_cfg)

rag = SmartRAG::SmartRAG.new(rag_config)
rag_client = SmartBrain::Adapters::SmartRag::DirectClient.new(rag: rag)

SmartBrain.configure(smart_rag_client: rag_client)
engine = SmartAgent::Engine.new('./config/example_agent.yml')
agent = engine.build_agent(:brain_assistant)

session_id = 'smartagent-smartbrain-demo'
user_messages = [
  '请记住：SmartRAG 作为 SmartBrain 的底层基础库，提供存储与检索服务',
  '继续这个话题，SmartBrain 默认使用哪种数据库？'
]

def build_worker_input(context, user_message)
  {
    context_id: context[:context_id],
    working_summary: context[:working_summary],
    recent_turns: context[:recent_turns],
    evidence: context[:evidence],
    latest_user_message: user_message,
    constraints: context[:constraints]
  }.to_json
end

user_messages.each_with_index do |user_message, idx|
  # 1) SmartBrain composes context (will call SmartRAG when planner enables resource retrieval).
  context = SmartBrain.compose_context(
    session_id: session_id,
    user_message: user_message,
    agent_state: { agent: 'SmartAgent', turn: idx + 1 }
  )

  # 2) SmartAgent executes the real call_worker flow.
  assistant_message = agent.please(build_worker_input(context, user_message))

  # 3) SmartBrain commits this turn.
  commit = SmartBrain.commit_turn(
    session_id: session_id,
    turn_events: {
      messages: [
        { role: 'user', content: user_message },
        { role: 'assistant', content: assistant_message.to_s }
      ],
      decisions: (idx.zero? ? [{ key: 'decision:smartbrain:storage', decision: 'Use Postgres by default' }] : [])
    }
  )

  resource_hits = Array(context[:evidence]).count { |e| e[:source] == 'resource' }
  memory_hits = Array(context[:evidence]).count { |e| e[:source] == 'memory' }

  puts "\n=== Turn #{idx + 1} ==="
  puts "context_id: #{context[:context_id]}"
  puts "request_id: #{context.dig(:debug, :trace, :request_id)}"
  puts "plan_id: #{context.dig(:debug, :trace, :plan_id)}"
  puts "commit_id: #{commit[:commit_id]}"
  puts "evidence(memory/resource): #{memory_hits}/#{resource_hits}"
  puts "assistant: #{assistant_message}"
end
