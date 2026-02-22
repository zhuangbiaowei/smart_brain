#!/usr/bin/env ruby
# frozen_string_literal: true

# =============================================================================
# SmartBrain + SmartRAG + SmartAgent 真实多轮对话演示
#
# 本示例演示：
# 1. 真实调用 SmartRAG 进行文档存储和检索
# 2. 真实调用 SmartAgent 与 LLM (Ollama) 对话
# 3. SmartBrain 在对话中维持记忆和上下文
# =============================================================================

require 'logger'
require 'json'

# 环境变量配置 - 使用轨迹流动 Kimi-K2.5 模型
ENV['SMARTRAG_DB_HOST'] ||= 'localhost'
ENV['SMARTRAG_DB_PORT'] ||= '5432'
ENV['SMARTRAG_DB_NAME'] ||= 'smart_rag_development'
ENV['SMARTRAG_DB_USER'] ||= 'rag_user'
ENV['SMARTRAG_DB_PASSWORD'] ||= 'rag_pwd'
ENV['EMBEDDING_MODEL'] = 'qwen3-embedding'

# 硅基流动 API 配置
SILICON_FLOW_API_KEY = 'sk-qbmqiwoyvswtyzrdjrojkaplerhwcwoloulqlxgcjfjxpmpw'
SILICON_FLOW_ENDPOINT = 'https://api.siliconflow.cn/v1/chat/completions'
SILICON_FLOW_MODEL = 'Pro/moonshotai/Kimi-K2.5'

# 加载依赖
require 'smart_prompt'
require 'smart_agent'
require_relative 'lib/smart_brain'
require_relative 'lib/smart_brain/adapters/smart_rag/direct_client'

# 加载 SmartRAG
begin
  require 'sequel'
  Sequel.extension 'pgvector'
rescue LoadError
  # pgvector extension not available
end

begin
  require '/home/mlf/smart_ai/smart_rag/lib/smart_rag'
rescue LoadError => e
  warn "SmartRAG load failed: #{e.message}"
  exit 1
end

puts "=" * 80
puts "SmartBrain + SmartRAG + SmartAgent 真实多轮对话演示"
puts "使用模型: 硅基流动 Pro/moonshotai/Kimi-K2.5"
puts "=" * 80

# =============================================================================
# 步骤 1: 初始化 SmartRAG
# =============================================================================

puts "\n📚 初始化 SmartRAG..."

rag_config = {
  database: {
    adapter: 'postgresql',
    host: ENV['SMARTRAG_DB_HOST'] || 'localhost',
    port: (ENV['SMARTRAG_DB_PORT'] || '5432').to_i,
    database: ENV['SMARTRAG_DB_NAME'] || 'smart_rag_development',
    user: ENV['SMARTRAG_DB_USER'] || 'rag_user',
    password: ENV['SMARTRAG_DB_PASSWORD'] || 'rag_pwd'
  },
  llm: {
    provider: 'openai',
    api_key: SILICON_FLOW_API_KEY,
    endpoint: SILICON_FLOW_ENDPOINT,
    model: SILICON_FLOW_MODEL,
    temperature: 0.3
  },
  # Embedding 配置 - 禁用（轨迹流动暂不支持 embedding）
  embedding: {
    config_path: '/home/mlf/smart_ai/smart_rag/config/llm_config.yml'
  }
}

begin
  rag = SmartRAG::SmartRAG.new(rag_config)
  rag.logger = Logger.new(STDOUT)
  rag.logger.level = Logger::WARN  # 减少日志输出

  stats = rag.statistics
  puts "✓ SmartRAG 初始化成功"
  puts "  - 文档数: #{stats[:document_count]}"
  puts "  - 段落数: #{stats[:section_count]}"
  puts "  - 主题数: #{stats[:topic_count]}"
rescue StandardError => e
  warn "✗ SmartRAG 初始化失败: #{e.message}"
  warn "请确保 PostgreSQL 正在运行且数据库已配置"
  exit 1
end

# =============================================================================
# 步骤 2: 准备知识库文档（如果还没有）
# =============================================================================

puts "\n📄 检查知识库文档..."

# 定义要添加的示例文档
documents = [
  {
    title: "Ruby Programming Best Practices",
    url: "https://example.com/ruby-best-practices",
    content: <<~DOC
      # Ruby Programming Best Practices

      ## Naming Conventions

      - Use snake_case for methods and variables: `user_name`, `total_count`
      - Use CamelCase for class and module names: `UserAccount`, `OrderProcessor`
      - Use SCREAMING_SNAKE_CASE for constants: `MAX_RETRIES`, `DEFAULT_TIMEOUT`

      ## Code Organization

      - Keep methods short and focused (under 20 lines)
      - Use single responsibility principle
      - Prefer composition over inheritance
      - Write self-documenting code with clear method names

      ## Error Handling

      - Use specific exception classes
      - Avoid rescuing Exception class
      - Use ensure for cleanup operations
    DOC
  },
  {
    title: "PostgreSQL Performance Optimization",
    url: "https://example.com/postgresql-performance",
    content: <<~DOC
      # PostgreSQL Performance Optimization

      ## Connection Pooling

      - Use connection poolers like PgBouncer for high-concurrency applications
      - Recommended pool size: (core_count * 2) + effective_spindle_count
      - Monitor connection usage with pg_stat_activity

      ## Indexing Strategies

      - Create indexes on frequently queried columns
      - Use partial indexes for filtered queries
      - Consider covering indexes for index-only scans
      - Regularly analyze tables for query planner

      ## Query Optimization

      - Use EXPLAIN ANALYZE to understand query plans
      - Avoid SELECT * in production queries
      - Use appropriate data types for columns
    DOC
  },
  {
    title: "Introduction to pgvector",
    url: "https://example.com/pgvector-intro",
    content: <<~DOC
      # Introduction to pgvector

      ## Overview

      pgvector is a PostgreSQL extension for vector similarity search.
      It allows you to store and query high-dimensional vectors directly in PostgreSQL.

      ## Key Features

      - Vector data type with up to 16,000 dimensions
      - ivfflat and hnsw indexes for fast approximate nearest neighbor search
      - L2, inner product, and cosine distance metrics
      - ACID compliance through PostgreSQL

      ## Installation

      CREATE EXTENSION pgvector;

      CREATE TABLE items (id bigserial PRIMARY KEY, embedding vector(3));

      ## Use Cases

      - Semantic search for AI applications
      - Recommendation systems
      - Image similarity search
      - Document clustering
    DOC
  }
]

# 检查并添加文档
documents.each do |doc|
  # 检查是否已存在
  existing = rag.list_documents(search: doc[:title])
  if existing[:documents].any? { |d| d[:title] == doc[:title] }
    puts "  ✓ 文档已存在: #{doc[:title]}"
  else
    begin
      # 创建临时文件
      require 'tempfile'
      Tempfile.create(['doc', '.md']) do |file|
        file.write(doc[:content])
        file.flush

        result = rag.add_document(
          file.path,
          title: doc[:title],
          url: doc[:url],
          generate_embeddings: false,
          generate_tags: false
        )
        puts "  ✓ 添加文档: #{doc[:title]} (ID: #{result[:document_id]})"
      end
    rescue StandardError => e
      puts "  ✗ 添加失败: #{doc[:title]} - #{e.message}"
    end
  end
end

# =============================================================================
# 步骤 3: 初始化 SmartBrain 和 SmartAgent
# =============================================================================

puts "\n🧠 初始化 SmartBrain..."

rag_client = SmartBrain::Adapters::SmartRag::DirectClient.new(rag: rag)
SmartBrain.configure(smart_rag_client: rag_client)
puts "✓ SmartBrain 初始化成功"

puts "\n🤖 初始化 SmartAgent..."
engine = SmartAgent::Engine.new('./config/example_agent.yml')
agent = engine.build_agent(:brain_assistant)
puts "✓ SmartAgent 初始化成功"
puts "  - 使用模型: #{SILICON_FLOW_MODEL}"

# =============================================================================
# 步骤 4: 定义多轮对话
# =============================================================================

session_id = "real-demo-#{Time.now.to_i}"

puts "\n" + "=" * 80
puts "开始多轮对话 (Session: #{session_id})"
puts "=" * 80

# 定义对话流程
conversations = [
  {
    turn: 1,
    user_message: "你好，我正在学习 Ruby，想了解一下命名规范。",
    extract_events: {
      goals: [
        { key: 'goal:learn:ruby', goal: '学习 Ruby 编程规范' }
      ],
      entities: [
        { key: 'entity:lang:ruby', name: 'Ruby', canonical: 'ruby', kind: 'language', remember: true }
      ]
    }
  },
  {
    turn: 2,
    user_message: "类名应该用什么风格？",
    extract_events: {
      decisions: [
        { key: 'decision:ruby:class_naming', decision: 'Ruby 类名使用 CamelCase' }
      ]
    }
  },
  {
    turn: 3,
    user_message: "明白了。现在我打算用 PostgreSQL 作为数据库，有什么性能建议吗？",
    extract_events: {
      goals: [
        { key: 'goal:learn:postgresql', goal: '学习 PostgreSQL 性能优化' }
      ],
      entities: [
        { key: 'entity:db:postgresql', name: 'PostgreSQL', canonical: 'postgresql', kind: 'database', remember: true }
      ]
    }
  },
  {
    turn: 4,
    user_message: "连接池大小一般怎么设置？",
    extract_events: {
      decisions: [
        { key: 'decision:pg:pool_size', decision: '连接池大小公式: (core_count * 2) + effective_spindle_count' }
      ]
    }
  },
  {
    turn: 5,
    user_message: "我听说有个叫 pgvector 的扩展，它适合什么场景？",
    extract_events: {
      entities: [
        { key: 'entity:ext:pgvector', name: 'pgvector', canonical: 'pgvector', kind: 'extension', remember: true }
      ]
    }
  }
]

# =============================================================================
# 步骤 5: 执行多轮对话
# =============================================================================

def build_worker_input(context, user_message)
  evidence_text = ""
  if context[:evidence] && !context[:evidence].empty?
    evidence_text = "\n\n## Evidence from Knowledge Base\n\n"
    context[:evidence].first(3).each_with_index do |ev, idx|
      evidence_text += "#{idx + 1}. #{ev[:title]}\n"
      evidence_text += "   #{ev[:snippet]}\n\n"
    end
  end

  # working_summary is a String, not a Hash
  summary_text = ""
  if context[:working_summary] && context[:working_summary].is_a?(String)
    summary_text = "\n\n## Conversation Summary\n\n#{context[:working_summary]}"
  end

  # Build the text parameter for the template
  context_text = "## User Message\n#{user_message}\n"
  context_text += summary_text if summary_text && !summary_text.empty?
  context_text += evidence_text if evidence_text && !evidence_text.empty?

  # Return string (agent.please expects a string)
  context_text
end

conversations.each do |conv|
  puts "\n" + "-" * 80
  puts "【第 #{conv[:turn]} 轮】"
  puts "-" * 80

  user_message = conv[:user_message]
  puts "\n👤 用户: #{user_message}"

  # 1. SmartBrain 组合上下文
  context = SmartBrain.compose_context(
    session_id: session_id,
    user_message: user_message,
    agent_state: { turn: conv[:turn] }
  )

  # 显示检索结果
  if context[:evidence] && !context[:evidence].empty?
    puts "\n🔍 SmartBrain 检索结果:"
    memory_count = context[:evidence].count { |e| e[:source] == 'memory' }
    resource_count = context[:evidence].count { |e| e[:source] == 'resource' }
    puts "   记忆: #{memory_count} | 资源: #{resource_count}"

    context[:evidence].first(3).each do |ev|
      icon = ev[:source] == 'memory' ? '💭' : '📄'
      puts "   #{icon} #{ev[:title]} (score: #{(ev[:score] || 0).round(2)})"
    end
  end

  # 2. SmartAgent 调用 LLM
  puts "\n🤖 SmartAgent 调用 LLM..."
  begin
    assistant_response = agent.please(build_worker_input(context, user_message))

    # 只显示响应的前一部分，避免输出过长
    display_text = assistant_response.to_s.strip
    if display_text.length > 300
      display_text = display_text[0..300] + "..."
    end
    puts "\n📝 助手回复:"
    puts "   #{display_text.gsub("\n", "\n   ")}"
  rescue StandardError => e
    puts "   ✗ LLM 调用失败: #{e.message}"
    puts "   错误类型: #{e.class}"
    puts "   堆栈: #{e.backtrace.first(5).join("\n         ")}"
    assistant_response = "抱歉，我暂时无法回答这个问题。"
  end

  # 3. SmartBrain 提交本轮
  turn_events = {
    messages: [
      { role: 'user', content: user_message },
      { role: 'assistant', content: assistant_response.to_s }
    ]
  }

  # 添加提取的事件
  if conv[:extract_events]
    turn_events.merge!(conv[:extract_events])
  end

  commit = SmartBrain.commit_turn(
    session_id: session_id,
    turn_events: turn_events
  )

  puts "\n💾 SmartBrain 提交:"
  puts "   - commit_id: #{commit[:commit_id][0..7]}..."
  puts "   - 记忆项: #{commit[:memory_written] ? commit[:memory_written][:count] : 0} 条"
  if commit[:summary] && commit[:summary][:triggered]
    puts "   - 总结更新: #{commit[:summary][:trigger_reason]}"
  end
end

# =============================================================================
# 步骤 6: 展示对话总结
# =============================================================================

puts "\n" + "=" * 80
puts "对话总结"
puts "=" * 80

diagnostics = SmartBrain.diagnostics

# 获取 Working Summary
final_summary = diagnostics.dig(:summaries, session_id)
if final_summary
  puts "\n📝 Working Summary:"
  puts final_summary[:text] if final_summary[:text]
end

# 统计信息
session_turns = diagnostics[:turns]&.select { |t| t[:session_id] == session_id } || []
puts "\n📊 统计信息:"
puts "   - 总轮数: #{session_turns.size}"
puts "   - Session ID: #{session_id}"

# 检索到的资源证据
resource_evidence_count = session_turns.sum do |turn|
  (turn[:context]&.dig(:evidence) || []).count { |e| e[:source] == 'resource' }
end
puts "   - 资源证据检索次数: #{resource_evidence_count}"

puts "\n" + "=" * 80
puts "演示结束！"
puts "=" * 80
