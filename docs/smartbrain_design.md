## 1. 定位与总体目标

### 1.1 SmartBrain 定位
SmartBrain 是 **Agent Memory Runtime（记忆运行时）+ Context Composer（上下文调度器）**，负责把“对话事件、工具调用结果、引用的资源”转化为可检索、可治理、可解释的长期记忆，并在每轮对话前生成模型所需的最小充分上下文。

SmartBrain 的核心职责：
- 事件真相层：记录每轮对话与工具调用（可回放、可审计）
- 记忆抽取与巩固：从事件中抽取 profile/preferences/tasks/decisions/entities 等结构化记忆，并维护滚动摘要
- 检索计划：理解当前对话意图，生成 `RetrievalPlan`（多模式、预算、过滤）
- 多源检索与融合：从 **SmartBrain MemoryStore** 与 **SmartRAG ResourceStore** 召回证据，统一重排
- 上下文装配：产出 `ContextPackage`（system blocks + summary + recent turns + evidence + user_message）

---

## 2. 与 SmartRAG 的关系（必须清晰的边界）

### 2.1 两种“记忆”的严格分工
SmartBrain 将 Agent 的可用信息分为两类：

1) **Conversation Memory（对话记忆）** — SmartBrain 自己负责  
- 原始事件：turn/messages/tool_calls/refs  
- 结构化记忆：profile/preferences/tasks/decisions/entities/events  
- 滚动摘要：working_summary  
特点：强时序、强语境、更新频繁、需要写入门控与冲突管理。

2) **Resource Memory（资源记忆）** — SmartRAG 负责  
- 文档/网页/仓库资料/规范等长期资源
- 分块、embedding、FTS、混合检索与（可选）rerank
特点：相对静态、内容大、需要高质量检索与证据定位。

> 结论：**SmartRAG 是 SmartBrain 的“资源知识库后端”**。SmartBrain 不复制 SmartRAG 的索引能力，只通过契约调用它。

### 2.2 SmartBrain 如何使用 SmartRAG（调用链）
SmartBrain 在 `compose_context` 时执行：

1) **意图分析**（LLM，本地 Qwen3）：判定本轮是否需要资源检索（Resource Retrieval）以及检索模式与范围  
2) 生成 `RetrievalPlan`（同一份 plan 可分发给两类检索器）：
   - 子计划 A：面向 SmartBrain MemoryStore（对话记忆库）
   - 子计划 B：面向 SmartRAG（资源知识库）
3) **调用 SmartRAG**：`SmartRAG.retrieve(plan)` → `EvidencePack`（资源证据）
4) SmartBrain 自身检索：Exact/Semantic/Relational（对话记忆证据）
5) **多源融合与统一 rerank**：合并证据 → 去重 → rerank（qwen3-reranker）→ diversity 约束
6) **上下文装配**：形成 `ContextPackage`

### 2.3 资源写入：SmartBrain 如何把“refs/产物”送进 SmartRAG（可选但推荐）
SmartBrain 在 `commit_turn` 处理 refs/产物时，按策略决定是否写入 SmartRAG：

- URL：抓取快照（或保存摘要）→ `SmartRAG.ingest(...)`
- 文件：保存文件摘要/元信息（必要时保存副本）→ `SmartRAG.ingest(...)`
- 工具产物：如生成的 spec/文档/代码片段 → 作为 `memory_snapshot` 或 `manual` 资源导入 SmartRAG

> 原则：SmartRAG 只收“值得长期引用的资源”；对话流水账不进入 SmartRAG。

---

## 3. 存储与部署选型（默认 Postgres，SQLite 仅可选）

### 3.1 默认：PostgreSQL（推荐）
原因：
- 事件与记忆数据天然关系型（会话/轮次/引用/实体）
- 便于做审计、查询、迁移
- 可与 SmartRAG 共用同一 Postgres 实例（不同 schema 或不同数据库）
- 如果未来需要 pgvector，也能统一（即使 SmartBrain 自身不一定需要 pgvector）

**推荐部署拓扑：**
- Postgres 实例：
  - `smart_rag` schema/db：由 SmartRAG 管理（documents/sections/fts/vector）
  - `smart_brain` schema/db：由 SmartBrain 管理（events/memory/entities/summary）
- SmartBrain 通过 SmartRAG 的 Ruby API 或 HTTP endpoint 调用检索（两者择一）

### 3.2 可选：SQLite（开发/单机轻量模式）
SQLite 仅建议用于：
- 本地快速开发与 demo
- 轻量 CLI、无需并发、多会话规模小

**注意**：SQLite 不是设计依赖；任何 SQLite-only 的能力都必须能迁移到 Postgres。

---

## 4. 总体架构（模块）

### 4.1 核心模块
1) **EventStore（Postgres）**  
   记录真相：turn/messages/tool_calls/refs，可回放。

2) **MemoryExtractor（LLM + 规则）**  
   从事件抽取结构化记忆（profile/preferences/tasks/decisions/entities/events）。

3) **Consolidator（摘要与冲突管理）**  
   - working_summary（滚动摘要）
   - core memory（可钉住的稳定记忆块）
   - 冲突合并/版本管理（superseded/retracted）

4) **RetrievalPlanner（LLM）**  
   生成 `RetrievalPlan`（多模式、预算、过滤、query expansion）。

5) **Memory Retrievers（SmartBrain 自己的检索）**
   - ExactRetriever：FTS/BM25（messages + memory_chunks）
   - SemanticRetriever：可选（若不想引入向量可先不做；推荐后续用 pgvector 或外部 embedding 索引）
   - RelationalRetriever：entity_mentions 聚合（关联分析）

6) **ResourceRetriever（SmartRAG Adapter）**
   - `retrieve(plan)`：调用 SmartRAG，得到 EvidencePack（资源证据）

7) **Fusion + Rerank**
   - 合并多路候选 → 去重 → rerank（qwen3-reranker）→ diversity 约束

8) **ContextComposer**
   - 按槽位装配上下文（system blocks / summary / recent turns / evidence / user）

9) **ModelProvider（本地 ollama）**
   - complete（planner/extractor/summary）
   - rerank（统一重排）
   - embedding（可选：若 SmartBrain 自身做 semantic retriever）

---

## 5. 数据模型（Postgres 优先）

### 5.1 EventStore
- `sessions(id, created_at, metadata_json)`
- `turns(id, session_id, seq, created_at)`
- `messages(id, turn_id, role, content, model, created_at, meta_json)`
- `tool_calls(id, turn_id, name, args_json, result_json, status, created_at)`
- `refs(id, turn_id, ref_type[file|url|artifact], ref_uri, ref_meta_json, created_at)`

### 5.2 MemoryStore（结构化）
- `memory_items(id, type, key, value_json, confidence, status, source_turn_id, updated_at)`
- `memory_chunks(id, memory_item_id, text, tsv, meta_json)`
  - `tsv` 用于 FTS（中文可用 pg_jieba）
  - embedding 字段 **不是必须**（如果引入 semantic retriever 再加）

### 5.3 Entities（关联检索）
- `entities(id, name, kind, canonical_id)`
- `entity_mentions(id, entity_id, turn_id, message_id, span_json, created_at)`

---

## 6. 核心接口与运行时链路

### 6.1 compose_context
```ruby
SmartBrain.compose_context(
  session_id:,
  user_message:,
  agent_state: {}
) => ContextPackage
```

执行步骤（建议固定顺序）：

1. Load：读取 core memory + working_summary + recent_turns window
2. Plan：RetrievalPlanner 生成 RetrievalPlan（含是否调用 SmartRAG）
3. Retrieve：

   * 从 SmartBrain MemoryStore 检索（exact/relational，semantic 可选）
   * 调用 SmartRAG.retrieve(plan) 获取资源 EvidencePack（如需要）
4. Fuse：合并候选证据 → 去重 → rerank → diversity
5. Compose：输出 ContextPackage（带 debug explain，开发期强烈建议打开）

### 6.2 commit_turn

```ruby
SmartBrain.commit_turn(
  session_id:,
  turn_events:
) => CommitResult
```

turn_events 至少包含：

* user message
* assistant message（含 tool calls）
* tool results
* refs（文件、URL、artifact）

执行步骤：

1. Persist：写入 EventStore（真相层）
2. Extract：MemoryExtractor 抽取 memory_items（写入门控）
3. Consolidate：更新 working_summary / core memory / 冲突版本
4. Optional Ingest：按策略把 refs/产物导入 SmartRAG（作为资源知识）

---

## 7. 多源检索与融合策略（关键）

### 7.1 召回来源

* **对话记忆召回**（SmartBrain）：

  * exact：FTS/BM25（messages/memory_chunks）
  * relational：entities/refs 聚合
  * semantic：可选（引入 pgvector/embedding 后开启）
* **资源证据召回**（SmartRAG）：

  * exact/semantic/hybrid：由 SmartRAG 执行
  * 返回 EvidencePack（包含 signals）

### 7.2 融合与去重

合并候选后去重建议按以下 key：

* resource：`document_id + section_id (+chunk_index)`
* memory：`memory_item_id` 或 `turn_id + message_id`

去重后保留最高 `rerank_score` 或融合分。

### 7.3 统一 rerank（推荐）

即使 SmartRAG 自己有 rerank，SmartBrain 仍建议做一次“跨源统一 rerank”：

* 输入：query（用户当前问题）+ 候选 snippets
* 输出：统一排序分
  好处：避免“资源证据”与“记忆证据”无法比较。

### 7.4 多样性（diversity）约束

* 同一 document 不超过 N 条
* 同一 source_uri/domain 不超过 M 条
* memory/resource 证据比例可配置（例如 40/60）

---

## 8. 上下文装配（ContextPackage）

槽位推荐固定为：

1. `system_blocks`：core profile + preferences + policies
2. `working_summary`：滚动摘要
3. `recent_turns`：最近窗口
4. `evidence`：检索证据（资源 + 记忆，带来源）
5. `user_message`

SmartBrain 必须承担 token 预算责任：

* snippet 长度限制
* 证据条数限制
* recent window 轮数限制
* summary 长度限制

---

## 9. 本地模型调用（ollama + Qwen3-*）

* Planner/Extractor/Summarizer：`qwen3`
* Reranker：`qwen3-reranker`
* Embedding（可选）：`qwen3-embedding`

> 注意：SmartBrain 不需要强制自己做 embedding 检索；资源语义检索主要依赖 SmartRAG。

---

## 10. MVP 路线（与 SmartRAG 强绑定）

### MVP-1（先跑通主链路）

* EventStore（Postgres）+ commit_turn
* working_summary + recent window
* RetrievalPlanner（只生成 exact/hybrid，且“是否调用 SmartRAG”）
* ResourceRetriever：调用 SmartRAG.retrieve(plan) 并拿到 EvidencePack
* ContextComposer：输出 ContextPackage（含 evidence）

> 此阶段 SmartBrain **可以不做自身 semantic 检索**，只做 exact + relational（对话侧） + SmartRAG（资源侧）。

### MVP-2（提升对话侧检索与关联）

* memory_chunks + FTS
* entities + mentions（关联分析）
* 跨源统一 rerank + diversity

### MVP-3（精细化治理）

* 写入门控可配置化（brain.yml）
* 冲突与撤回
* refs/产物 ingest 到 SmartRAG 的策略成熟化

---

## 11. 交付物清单（SmartBrain）

* `docs/smartbrain_design.md`（本文）
* `docs/retrieval_plan.md`（契约：SmartBrain ↔ SmartRAG）
* `docs/context_package.md`（契约：SmartBrain → SmartBot/SmartPrompt）
* `docs/memory_types.md`（记忆分类与 key 规则）
* `docs/policies.md`（retention/summary/conflict/diversity）
* 代码模块：

  * `lib/smart_brain/event_store/*`
  * `lib/smart_brain/memory_extractor/*`
  * `lib/smart_brain/retrieval_planner/*`
  * `lib/smart_brain/retrievers/*`（含 SmartRAG adapter）
  * `lib/smart_brain/context_composer/*`
  * `lib/smart_brain/model_provider/*`
* 测试：

  * `spec/compose_context_spec.rb`
  * `spec/commit_turn_spec.rb`
  * `spec/integration_smart_rag_adapter_spec.rb`
