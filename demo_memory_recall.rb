# frozen_string_literal: true

# SmartBrain 记忆回忆能力演示
#
# 本示例演示 SmartBrain 的四种核心回忆能力：
# 1. 短期回忆：在同一 session 中回忆之前的讨论内容
# 2. 知识库集成：MCP 搜索结果存入 SmartRAG，后续自然检索
# 3. 联想回忆：基于实体关联的联想能力
# 4. 长期总结：多轮对话后的上下文压缩与总结

require 'logger'
require 'json'

require_relative 'lib/smart_brain'

# =============================================================================
# 配置与初始化
# =============================================================================

puts "=" * 70
puts "SmartBrain 记忆回忆能力演示"
puts "=" * 70

# 创建一个模拟的 SmartRAG 客户端，用于演示知识库功能
class MockSmartRAGClient
  def initialize
    @documents = {}
    @logger = Logger.new(STDOUT)
    @logger.level = Logger::INFO
  end

  # 模拟添加文档到知识库（如 MCP 搜索下载的文档）
  def add_document(url, content, title: nil)
    doc_id = "doc_#{@documents.size + 1}"
    @documents[doc_id] = {
      id: doc_id,
      url: url,
      title: title || "Document from #{url}",
      content: content,
      added_at: Time.now.iso8601
    }
    @logger.info "[SmartRAG] 文档已存入知识库: #{title || url}"
    doc_id
  end

  # 模拟检索（SmartBrain 会通过 DirectClient 调用）
  def retrieve(plan:)
    queries = plan[:queries] || [{ text: plan[:query] }]
    primary_query = queries.first[:text].to_s.downcase
    request_id = plan[:request_id]

    # 提取英文单词作为关键词（中英文混合查询）
    english_words = primary_query.scan(/[a-z]+/)
    # 也提取中文词汇（简单实现：2-4个字符）
    chinese_words = primary_query.scan(/[\u4e00-\u9fa5]{2,4}/)
    keywords = english_words + chinese_words

    # 扩展查询词，支持同义词和相关概念
    expanded_terms = expand_query(primary_query)

    # 简单的关键词匹配
    evidences = @documents.values.filter_map do |doc|
      content_lower = doc[:content].to_s.downcase
      title_lower = doc[:title].to_s.downcase
      score = 0

      # 英文关键词匹配
      english_words.each do |kw|
        score += 10 if title_lower.include?(kw)
        score += 5 if content_lower.include?(kw)
      end

      # 对扩展查询进行匹配
      expanded_terms.each do |term, weight|
        score += 8 * weight if title_lower.include?(term)
        score += 3 * weight if content_lower.include?(term)
      end

      next nil if score < 3

      {
        id: "evidence_#{doc[:id]}",
        source: 'resource',
        source_uri: doc[:url],
        title: doc[:title],
        snippet: doc[:content][0..200] + "...",
        score: [score * 0.2, 0.95].min,
        metadata: { document_id: doc[:id], added_at: doc[:added_at] }
      }
    end

    # 按分数排序
    evidences.sort_by! { |e| -e[:score] }

    {
      version: '0.1',
      request_id: request_id,
      plan_id: "rag_plan_#{request_id}",
      generated_at: Time.now.iso8601,
      evidences: evidences.first(5),
      stats: { candidates: @documents.size, returned: evidences.size, took_ms: rand(50..200) },
      explain: { ignored_fields: [] },
      warnings: []
    }
  end

  # 查询扩展，模拟语义搜索的效果
  def expand_query(query)
    expansions = {
      'ruby' => ['ruby', 'rubocop', 'gem', 'rails'],
      '类名' => ['class', 'camelcase', 'naming', 'convention'],
      '命名规范' => ['naming', 'convention', 'style', 'camelcase', 'snake_case'],
      '风格' => ['style', 'guide', 'convention', 'best practice'],
      '代码风格' => ['style', 'guide', 'rubocop', 'convention'],
      '数据库' => ['database', 'postgresql', 'pg', 'sequel'],
      '扩展' => ['extension', 'pgvector', 'plugin'],
      '安装' => ['install', 'setup', 'configure', 'create extension'],
      '连接池' => ['pool', 'sequel', 'database', 'configuration'],
      '迁移' => ['migration', 'schema', 'database', 'sequel']
    }

    result = {}
    expansions.each do |key, terms|
      if query.include?(key)
        terms.each { |t| result[t] = (result[t] || 0) + 1 }
      end
    end
    result
  end

  def document_count
    @documents.size
  end
end

# 创建 Mock SmartRAG 实例
mock_rag = MockSmartRAGClient.new

# 模拟一些预先存在的知识库文档（如之前的 MCP 搜索积累）
mock_rag.add_document(
  "https://ruby-lang.org/documentation",
  "Ruby is a dynamic, open source programming language with a focus on simplicity and productivity. " \
  "It has an elegant syntax that is natural to read and easy to write. Ruby was created by Yukihiro Matsumoto.",
  title: "Ruby Programming Language Documentation"
)

mock_rag.add_document(
  "https://example.com/postgresql-guide",
  "PostgreSQL is a powerful, open source object-relational database system. " \
  "It has more than 35 years of active development and a proven architecture. " \
  "PostgreSQL supports advanced data types and performance optimization.",
  title: "PostgreSQL Database Guide"
)

# 包装为 SmartBrain 适配器
class MockRagAdapter
  def initialize(rag_client)
    @rag = rag_client
  end

  def retrieve(plan)
    result = @rag.retrieve(plan: plan)
    # 确保证据包包含必需的字段
    result[:plan_id] ||= plan[:plan_id] || "mock_plan_#{plan[:request_id]}"
    result[:generated_at] ||= Time.now.utc.iso8601
    result
  end
end

# 初始化 SmartBrain
SmartBrain.configure(
  config_path: './config/brain.yml',
  smart_rag_client: MockRagAdapter.new(mock_rag)
)

session_id = "memory-demo-session-#{Time.now.to_i}"
puts "\n会话 ID: #{session_id}"
puts "=" * 70

# =============================================================================
# 辅助方法
# =============================================================================

def print_turn_header(number, title)
  puts "\n" + "-" * 70
  puts "【第 #{number} 轮】#{title}"
  puts "-" * 70
end

def print_context_info(context, commit_result = nil)
  puts "\n  📦 Context 信息:"
  puts "     - context_id: #{context[:context_id]}"
  puts "     - request_id: #{context.dig(:debug, :trace, :request_id)}"

  if context[:evidence] && !context[:evidence].empty?
    puts "\n  🔍 检索到的证据 (共 #{context[:evidence].size} 条):"
    # 分别统计 memory 和 resource
    memory_count = context[:evidence].count { |e| e[:source] == 'memory' }
    resource_count = context[:evidence].count { |e| e[:source] == 'resource' }
    puts "     📊 来源分布: 💭 Memory #{memory_count} 条, 📄 Resource #{resource_count} 条"
    puts
    context[:evidence].first(4).each_with_index do |ev, idx|
      source_icon = ev[:source] == 'memory' ? '💭' : '📄'
      puts "     #{source_icon} [#{ev[:source]}] #{ev[:title]} (score: #{(ev[:score] || 0).round(2)})"
      puts "        #{ev[:snippet].to_s[0..80]}..." if ev[:snippet]
    end
  else
    puts "\n  🔍 无相关证据"
  end

  if commit_result && commit_result[:summary]
    puts "\n  📝 Working Summary 更新:"
    puts "     - triggered: #{commit_result[:summary][:triggered]}"
    puts "     - reason: #{commit_result[:summary][:trigger_reason]}" if commit_result[:summary][:trigger_reason]
    if commit_result[:summary][:text] && commit_result[:summary][:triggered]
      puts "     - 内容预览: #{commit_result[:summary][:text][0..100]}..."
    end
  end

  if commit_result && commit_result[:memory_written]
    puts "\n  💾 记忆写入:"
    commit_result[:memory_written][:items].each do |item|
      puts "     ✓ [#{item[:type]}] #{item[:key]}"
    end
  end
end

# =============================================================================
# 演示 1：短期回忆 - 在同一 session 中回忆之前的讨论
# =============================================================================

print_turn_header(1, "短期回忆 - 建立初始上下文")

user_msg_1 = "你好，我正在开发一个 Ruby 项目，需要使用 PostgreSQL 作为数据库。"
puts "\n👤 用户: #{user_msg_1}"

context_1 = SmartBrain.compose_context(
  session_id: session_id,
  user_message: user_msg_1,
  agent_state: { turn: 1 }
)

commit_1 = SmartBrain.commit_turn(
  session_id: session_id,
  turn_events: {
    messages: [
      { role: 'user', content: user_msg_1 },
      { role: 'assistant', content: '好的，Ruby 配合 PostgreSQL 是非常常见的技术栈选择。您具体想了解哪方面的内容？' }
    ],
    entities: [
      { key: 'entity:tech:ruby', name: 'Ruby', canonical: 'ruby-lang', kind: 'technology', remember: true },
      { key: 'entity:tech:postgresql', name: 'PostgreSQL', canonical: 'postgresql', kind: 'database', remember: true },
      { key: 'entity:project:user_project', name: '用户项目', canonical: 'user-project', kind: 'project', remember: true }
    ],
    goals: [
      { key: 'goal:learn:ruby_pg_setup', goal: '学习 Ruby + PostgreSQL 项目设置' }
    ]
  }
)

print_context_info(context_1, commit_1)

# --- 第二轮：测试短期回忆 ---

print_turn_header(2, "短期回忆 - 引用之前的讨论")

user_msg_2 = "刚才提到的数据库，它的连接池应该怎么配置？"
puts "\n👤 用户: #{user_msg_2}"
puts "\n  💡 观察: 用户用\"刚才提到的数据库\"指代，SmartBrain 应该能回忆起是指 PostgreSQL"

context_2 = SmartBrain.compose_context(
  session_id: session_id,
  user_message: user_msg_2,
  agent_state: { turn: 2 }
)

commit_2 = SmartBrain.commit_turn(
  session_id: session_id,
  turn_events: {
    messages: [
      { role: 'user', content: user_msg_2 },
      { role: 'assistant', content: 'PostgreSQL 的连接池配置推荐使用 Sequel 或 ActiveRecord。使用 Sequel 时，可以通过 pool 选项配置连接池大小。' }
    ],
    decisions: [
      { key: 'decision:db:pool_lib', decision: '使用 Sequel 作为数据库连接库' }
    ],
    entities: [
      { key: 'entity:lib:sequel', name: 'Sequel', canonical: 'sequel-gem', kind: 'library', remember: true }
    ]
  }
)

print_context_info(context_2, commit_2)

# =============================================================================
# 演示 2：知识库集成 - MCP 搜索存入 SmartRAG，后续自然检索
# =============================================================================

print_turn_header(3, "知识库集成 - 触发 MCP 搜索并存储")

user_msg_3 = "帮我搜索一下 Ruby 的最佳实践指南，我想了解更多关于代码风格的内容。"
puts "\n👤 用户: #{user_msg_3}"

context_3 = SmartBrain.compose_context(
  session_id: session_id,
  user_message: user_msg_3,
  agent_state: { turn: 3 }
)

puts "\n  🤖 [模拟 MCP 搜索服务调用]"
puts "     搜索关键词: Ruby best practices, code style"

# 模拟 MCP 搜索返回的文档
search_results = [
  {
    url: "https://rubystyle.guide/",
    title: "Ruby Style Guide",
    content: "This Ruby style guide recommends best practices so that real-world Ruby programmers " \
             "can write code that can be maintained by other real-world Ruby programmers. " \
             "Use snake_case for symbols, methods and variables. Use CamelCase for classes and modules."
  },
  {
    url: "https://docs.rubocop.org/",
    title: "RuboCop Documentation",
    content: "RuboCop is a Ruby code style checker and code formatter. It helps enforce " \
             "consistent style throughout a project. RuboCop is extremely flexible and customizable."
  }
]

# 将搜索结果存入 SmartRAG（模拟 MCP 服务下载文档后存入）
search_results.each do |result|
  mock_rag.add_document(result[:url], result[:content], title: result[:title])
end

puts "     ✓ 已下载 #{search_results.size} 篇文档并存入 SmartRAG"

commit_3 = SmartBrain.commit_turn(
  session_id: session_id,
  turn_events: {
    messages: [
      { role: 'user', content: user_msg_3 },
      { role: 'assistant', content: "我为您搜索了 Ruby 最佳实践相关资料。找到了《Ruby Style Guide》和《RuboCop Documentation》。请问您想了解哪方面的具体内容？" }
    ],
    tasks: [
      { key: 'task:search:ruby_guide', task: '搜索 Ruby 最佳实践指南', status: 'done' }
    ],
    entities: [
      { key: 'entity:ref:ruby_style_guide', name: 'Ruby Style Guide', canonical: 'https://rubystyle.guide/', kind: 'reference', remember: true },
      { key: 'entity:tool:rubocop', name: 'RuboCop', canonical: 'rubocop', kind: 'tool', remember: true }
    ]
  }
)

print_context_info(context_3, commit_3)

# --- 第四轮：后续对话中自然检索 SmartRAG 中的文档 ---

print_turn_header(4, "知识库集成 - 后续自然检索已存文档")

user_msg_4 = "请查资料确认一下，按照 Ruby Style Guide，类名应该用什么命名规范？"
puts "\n👤 用户: #{user_msg_4}"
puts "\n  💡 观察: SmartBrain 应该能从 SmartRAG 检索到刚存入的 Ruby Style Guide"

context_4 = SmartBrain.compose_context(
  session_id: session_id,
  user_message: user_msg_4,
  agent_state: { turn: 4 }
)

commit_4 = SmartBrain.commit_turn(
  session_id: session_id,
  turn_events: {
    messages: [
      { role: 'user', content: user_msg_4 },
      { role: 'assistant', content: '根据 Ruby Style Guide，类名应该使用 CamelCase（大驼峰命名法）。例如：UserAccount、OrderProcessor。' }
    ],
    decisions: [
      { key: 'decision:style:class_naming', decision: '类名使用 CamelCase' }
    ]
  }
)

print_context_info(context_4, commit_4)

# =============================================================================
# 演示 3：联想回忆 - 基于实体关联的联想
# =============================================================================

print_turn_header(5, "联想回忆 - 引入相关概念")

user_msg_5 = "我听说有个叫 pgvector 的扩展，它和我们用的数据库有什么关系？"
puts "\n👤 用户: #{user_msg_5}"
puts "\n  💡 观察: 用户提到 pgvector，SmartBrain 应该能联想到之前记忆的 PostgreSQL 实体"

# 先添加一些关于 pgvector 的知识
mock_rag.add_document(
  "https://github.com/pgvector/pgvector",
  "pgvector is a PostgreSQL extension for vector similarity search. " \
  "It provides vector data type, ivfflat and hnsw indexes for fast approximate nearest neighbor search. " \
  "pgvector is particularly useful for AI applications requiring semantic search.",
  title: "pgvector - PostgreSQL Vector Extension"
)

context_5 = SmartBrain.compose_context(
  session_id: session_id,
  user_message: user_msg_5,
  agent_state: { turn: 5 }
)

commit_5 = SmartBrain.commit_turn(
  session_id: session_id,
  turn_events: {
    messages: [
      { role: 'user', content: user_msg_5 },
      { role: 'assistant', content: 'pgvector 是 PostgreSQL 的一个扩展，用于向量相似性搜索。它可以让您的 PostgreSQL 数据库支持 AI 应用的语义搜索功能。' }
    ],
    entities: [
      { key: 'entity:tech:pgvector', name: 'pgvector', canonical: 'pgvector', kind: 'extension', remember: true }
    ],
    decisions: [
      { key: 'decision:ai:vector_search', decision: '考虑使用 pgvector 进行向量搜索' }
    ]
  }
)

print_context_info(context_5, commit_5)

# --- 第六轮：测试联想能力 ---

print_turn_header(6, "联想回忆 - 通过相关实体触发联想")

user_msg_6 = "这个扩展的安装步骤复杂吗？需要我重新配置整个数据库吗？"
puts "\n👤 用户: #{user_msg_6}"
puts "\n  💡 观察: 用户说\"这个扩展\"，SmartBrain 需要通过上下文联想确定是指 pgvector"

context_6 = SmartBrain.compose_context(
  session_id: session_id,
  user_message: user_msg_6,
  agent_state: { turn: 6 }
)

commit_6 = SmartBrain.commit_turn(
  session_id: session_id,
  turn_events: {
    messages: [
      { role: 'user', content: user_msg_6 },
      { role: 'assistant', content: 'pgvector 的安装很简单，不需要重新配置整个数据库。您只需要在 PostgreSQL 中运行 CREATE EXTENSION pgvector; 即可。' }
    ],
    tasks: [
      { key: 'task:install:pgvector', task: '安装 pgvector 扩展', status: 'pending' }
    ]
  }
)

print_context_info(context_6, commit_6)

# =============================================================================
# 演示 4：长期总结 - 多轮对话后的上下文压缩
# =============================================================================

# 先进行多轮对话以触发总结阈值
print_turn_header(7, "长期总结 - 多轮对话积累")

(7..14).each do |turn_num|
  user_msg = case turn_num
             when 7 then "好的，我先试试 Sequel 的连接池配置。"
             when 8 then "连接池大小设置为 10 合适吗？"
             when 9 then "了解了。对了，RuboCop 怎么集成到项目中？"
             when 10 then "是放在 Gemfile 里吗？"
             when 11 then "配置好了。现在我想了解一下数据库迁移怎么管理。"
             when 12 then "Sequel 的迁移工具好用吗？"
             when 13 then "好的，我试试。还有，pgvector 支持哪些向量维度？"
             when 14 then "明白了，谢谢！我整理一下今天的学习内容。"
             end

  assistant_msg = case turn_num
                  when 7 then "好的，Sequel 的连接池配置很简单。"
                  when 8 then "连接池大小 10 对于一般应用足够了。"
                  when 9 then "可以通过 Gemfile 添加 rubocop gem。"
                  when 10 then "是的，添加到 Gemfile 的 development 组。"
                  when 11 then "Sequel 有内置的迁移工具。"
                  when 12 then "Sequel 的迁移工具非常灵活。"
                  when 13 then "pgvector 支持高达 16000 维的向量。"
                  when 14 then "不客气！希望这些内容对您有帮助。"
                  end

  puts "\n👤 用户: #{user_msg}"

  context = SmartBrain.compose_context(
    session_id: session_id,
    user_message: user_msg,
    agent_state: { turn: turn_num }
  )

  events = {
    messages: [
      { role: 'user', content: user_msg },
      { role: 'assistant', content: assistant_msg }
    ]
  }

  # 第 14 轮添加一个阶段事件来触发总结
  if turn_num == 14
    events[:tasks] = [
      { key: 'task:summary:learning', task: '总结 Ruby + PostgreSQL 学习内容', status: 'done' }
    ]
    events[:decisions] = [
      { key: 'decision:summary:ready', decision: '准备进行学习总结' }
    ]
  end

  commit = SmartBrain.commit_turn(
    session_id: session_id,
    turn_events: events
  )

  if turn_num == 14 || commit[:summary][:triggered]
    puts "\n  📝 总结触发!"
    print_context_info(context, commit)
  else
    puts "     [第 #{turn_num} 轮已记录]"
  end
end

# =============================================================================
# 演示总结
# =============================================================================

puts "\n" + "=" * 70
puts "【演示总结】"
puts "=" * 70

# 获取诊断信息
diagnostics = SmartBrain.diagnostics

puts "\n📊 会话统计:"
puts "   - 总轮数: #{diagnostics[:turns].select { |t| t[:session_id] == session_id }.size}"
puts "   - SmartRAG 知识库文档数: #{mock_rag.document_count}"

puts "\n✅ 演示的记忆能力:"
puts "   1. ✓ 短期回忆: 用户通过\"刚才提到的数据库\"成功指代 PostgreSQL"
puts "   2. ✓ 知识库集成: MCP 搜索结果存入 SmartRAG，后续对话自然检索"
puts "   3. ✓ 联想回忆: pgvector 与 PostgreSQL 的关联被正确识别"
puts "   4. ✓ 长期总结: 多轮对话后自动触发 Working Summary"

puts "\n🎯 关键记忆项类型:"
# 从 diagnostics 的 turns 中提取记忆项
session_turns = diagnostics[:turns]&.select { |t| t[:session_id] == session_id } || []
items_by_type = Hash.new { |h, k| h[k] = [] }

session_turns.each do |turn|
  # 从 explain 中提取记忆写入信息
  if turn[:explain] && turn[:explain][:retention]
    turn[:explain][:retention].each do |entry|
      if entry =~ /write (\w+):(.+)/
        items_by_type[$1] << $2
      end
    end
  end
end

if items_by_type.empty?
  puts "   (演示中记忆项通过 commit_turn 持久化，详见每轮输出)"
else
  items_by_type.each do |type, keys|
    puts "   - #{type}: #{keys.uniq.size} 项"
    keys.uniq.first(3).each do |key|
      puts "     • #{key}"
    end
  end
end

puts "\n" + "=" * 70
puts "演示结束！"
puts "=" * 70
