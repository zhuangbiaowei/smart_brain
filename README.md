# SmartBrain

SmartBrain 是一个面向 Agent 的记忆运行时（Memory Runtime）与上下文编排器（Context Composer）。

它的核心职责：
- `commit_turn`：记录事件真相并沉淀结构化记忆
- `compose_context`：在每轮请求前组装最小充分上下文
- 联动 SmartRAG：对话记忆由 SmartBrain 管理，资源检索由 SmartRAG 提供

## 当前进展

当前仓库已实现并打通：
- `commit_turn` / `compose_context` 主链路
- Retention / Consolidation / Retrieval / Composition 策略
- 检索器：exact + relational
- 融合层：去重、规则重排、多样性、预算截断
- SmartRAG 适配器：`NullClient` / `HttpClient` / `DirectClient`
- 契约与可观测：`request_id` / `plan_id` / `context_id` 全链路追踪
- RSpec 测试（单元 + 集成 + 回归）

## 项目结构

- `lib/smart_brain.rb`：入口 API
- `lib/smart_brain/runtime.rb`：主运行时编排
- `lib/smart_brain/contracts/`：RetrievalPlan / EvidencePack / ContextPackage 校验
- `lib/smart_brain/observability/`：日志与指标
- `lib/smart_brain/event_store/`：事件存储（当前内存实现）
- `lib/smart_brain/memory_store/`：记忆存储（当前内存实现）
- `lib/smart_brain/retrievers/`：exact/relational 检索
- `lib/smart_brain/fusion/`：多源融合
- `lib/smart_brain/context_composer/`：上下文装配
- `lib/smart_brain/adapters/smart_rag/`：SmartRAG 适配层
- `config/brain.yml`：策略配置
- `example.rb`：SmartBrain + SmartAgent + SmartPrompt + SmartRAG 联动示例
- `docs/`：设计与协议文档

## 安装

```bash
bundle install
```

如遇本地权限或 shared gem 污染，建议：

```bash
bundle config set --local path 'vendor/bundle'
bundle config set --local disable_shared_gems 'true'
```

## 快速开始（仅 SmartBrain）

```ruby
require_relative 'lib/smart_brain'

SmartBrain.configure

SmartBrain.commit_turn(
  session_id: 'demo',
  turn_events: {
    messages: [
      { role: 'user', content: '请记住：默认数据库是 Postgres。' },
      { role: 'assistant', content: '已记录。' }
    ],
    decisions: [
      { key: 'decision:smartbrain:storage', decision: 'Use Postgres by default' }
    ]
  }
)

context = SmartBrain.compose_context(
  session_id: 'demo',
  user_message: '继续并总结关键结论'
)

puts context[:context_id]
puts context.dig(:debug, :trace, :request_id)
puts context.dig(:debug, :trace, :plan_id)
```

## SmartRAG 集成方式

### 1) NullClient（默认）

不配置 `smart_rag_client` 时，资源证据为空，仅使用记忆侧证据。

### 2) HttpClient

```ruby
transport = lambda do |plan, timeout_seconds:|
  {
    plan_id: 'p1',
    supports_language_filter: true,
    evidences: []
  }
end

client = SmartBrain::Adapters::SmartRag::HttpClient.new(transport: transport, timeout_seconds: 2)
SmartBrain.configure(smart_rag_client: client)
```

### 3) DirectClient（当前示例使用）

```ruby
require '/home/mlf/smart_ai/smart_rag/lib/smart_rag'
require_relative 'lib/smart_brain/adapters/smart_rag/direct_client'

rag_config = SmartRAG::Config.load('/home/mlf/smart_ai/smart_rag/config/smart_rag.yml')
rag = SmartRAG::SmartRAG.new(rag_config)
client = SmartBrain::Adapters::SmartRag::DirectClient.new(rag: rag)

SmartBrain.configure(smart_rag_client: client)
```

## example.rb 说明（已更新）

`example.rb` 演示完整链路：
1. SmartBrain `compose_context`
2. SmartAgent 通过 `call_worker` 调用 SmartPrompt worker
3. SmartBrain `commit_turn`
4. 打印 `evidence(memory/resource)` 验证 SmartRAG 是否参与

示例依赖的本地文件：
- `config/example_agent.yml`
- `config/example_llm.yml`
- `agents/brain_assistant.rb`
- `workers/brain_assistant.rb`
- `templates/brain_assistant.erb`

运行：

```bash
bundle exec ruby example.rb
```

## 核心 API

### `SmartBrain.configure(config_path: nil, smart_rag_client: nil, clock: -> { Time.now.utc })`
初始化运行时并注入 SmartRAG 客户端（可选）。

### `SmartBrain.commit_turn(session_id:, turn_events:)`
写入事件、抽取记忆、冲突处理、摘要更新。

### `SmartBrain.compose_context(session_id:, user_message:, agent_state: {})`
生成 `ContextPackage`，内部包含检索计划与证据融合结果。

### `SmartBrain.diagnostics`
返回 compose/commit 观测日志与指标快照。

## 测试

```bash
rspec
```

## 常见问题

### 1) `cannot load such file -- sequel/extensions/pgvector`
当前示例已在 `example.rb` 做兼容处理（`Sequel.extension 'pgvector'` + 去除 `database.extensions` 连接参数）。

### 2) `Config file not found: config/llm_config.yml`
`example.rb` 已将 SmartRAG 里 EmbeddingService 的 `config_path` 注入为 `./config/example_llm.yml`。

### 3) `ruby-lsp: not found`
```bash
gem install --user-install ruby-lsp debug
```
并将用户 gem bin 加入 `PATH`。

## 路线图

- 将 EventStore/MemoryStore 从内存实现切换到 Postgres 实现
- 接入真实 reranker / embedding 模型
- 完善 SmartRAG ingest 与跨会话评估工具
