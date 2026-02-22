# SmartBrain

SmartBrain is an Agent Memory Runtime and Context Composer.

Core responsibilities:
- `commit_turn`: persist event truth and structured memory
- `compose_context`: build minimal, sufficient context per turn
- integrate with SmartRAG: SmartBrain handles conversation memory, SmartRAG handles resource retrieval

## Current Progress

The repository now includes a runnable v0.1 flow with:
- `commit_turn` / `compose_context` end-to-end pipeline
- retention / consolidation / retrieval / composition policies
- retrievers: exact + relational
- fusion: dedupe, rule-based rerank, diversity, budget truncation
- SmartRAG adapters: `NullClient`, `HttpClient`, `DirectClient`
- traceability via `request_id` / `plan_id` / `context_id`
- RSpec coverage (unit + integration + regression)

## Project Layout

- `lib/smart_brain.rb`: public API
- `lib/smart_brain/runtime.rb`: runtime orchestration
- `lib/smart_brain/contracts/`: RetrievalPlan / EvidencePack / ContextPackage validation
- `lib/smart_brain/observability/`: logs and metrics
- `lib/smart_brain/event_store/`: event storage (in-memory currently)
- `lib/smart_brain/memory_store/`: memory storage (in-memory currently)
- `lib/smart_brain/retrievers/`: exact/relational retrievers
- `lib/smart_brain/fusion/`: multi-source fusion
- `lib/smart_brain/context_composer/`: context assembly
- `lib/smart_brain/adapters/smart_rag/`: SmartRAG adapters
- `config/brain.yml`: policy config
- `example.rb`: SmartBrain + SmartAgent + SmartPrompt + SmartRAG demo
- `docs/`: design and protocol documents

## Installation

```bash
bundle install
```

If you hit permission/shared-gem issues:

```bash
bundle config set --local path 'vendor/bundle'
bundle config set --local disable_shared_gems 'true'
```

## Quick Start (SmartBrain Only)

```ruby
require_relative 'lib/smart_brain'

SmartBrain.configure

SmartBrain.commit_turn(
  session_id: 'demo',
  turn_events: {
    messages: [
      { role: 'user', content: 'Remember this: default DB is Postgres.' },
      { role: 'assistant', content: 'Saved.' }
    ],
    decisions: [
      { key: 'decision:smartbrain:storage', decision: 'Use Postgres by default' }
    ]
  }
)

context = SmartBrain.compose_context(
  session_id: 'demo',
  user_message: 'Continue and summarize key points'
)

puts context[:context_id]
puts context.dig(:debug, :trace, :request_id)
puts context.dig(:debug, :trace, :plan_id)
```

## SmartRAG Integration Options

### 1) NullClient (default)

If no SmartRAG client is injected, resource evidence is empty.

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

### 3) DirectClient (used in `example.rb`)

```ruby
require '/home/mlf/smart_ai/smart_rag/lib/smart_rag'
require_relative 'lib/smart_brain/adapters/smart_rag/direct_client'

rag_config = SmartRAG::Config.load('/home/mlf/smart_ai/smart_rag/config/smart_rag.yml')
rag = SmartRAG::SmartRAG.new(rag_config)
client = SmartBrain::Adapters::SmartRag::DirectClient.new(rag: rag)

SmartBrain.configure(smart_rag_client: client)
```

## `example.rb` (Updated)

The example demonstrates the real loop:
1. SmartBrain `compose_context`
2. SmartAgent calls SmartPrompt worker via `call_worker`
3. SmartBrain `commit_turn`
4. prints `evidence(memory/resource)` so you can verify SmartRAG participation

Files used by the demo:
- `config/example_agent.yml`
- `config/example_llm.yml`
- `agents/brain_assistant.rb`
- `workers/brain_assistant.rb`
- `templates/brain_assistant.erb`

Run:

```bash
bundle exec ruby example.rb
```

## Core API

### `SmartBrain.configure(config_path: nil, smart_rag_client: nil, clock: -> { Time.now.utc })`
Initialize runtime and optionally inject a SmartRAG client.

### `SmartBrain.commit_turn(session_id:, turn_events:)`
Persist events, extract memory, resolve conflicts, update summary.

### `SmartBrain.compose_context(session_id:, user_message:, agent_state: {})`
Build a `ContextPackage` with planning and fused evidence.

### `SmartBrain.diagnostics`
Return observability snapshot for compose/commit logs and metrics.

## Test

```bash
rspec
```

## Troubleshooting

### 1) `cannot load such file -- sequel/extensions/pgvector`
`example.rb` already applies compatibility handling (`Sequel.extension 'pgvector'` and strips `database.extensions` from DB connect config).

### 2) `Config file not found: config/llm_config.yml`
`example.rb` injects `config_path: ./config/example_llm.yml` for SmartRAG EmbeddingService startup.

### 3) `ruby-lsp: not found`
```bash
gem install --user-install ruby-lsp debug
```
and ensure user gem `bin` is in `PATH`.

## Roadmap

- migrate EventStore/MemoryStore from in-memory to Postgres-backed implementations
- integrate real reranker/embedding models
- improve SmartRAG ingest pipeline and cross-session evaluation tooling
