# SmartBrain Ruby 开发待办（v0.1）

## 0. 目标与范围
- 目标：实现 `commit_turn` 与 `compose_context` 主链路，满足 `docs/policies.md` 的最低验收标准。
- 边界：SmartBrain 管理对话记忆与上下文装配；资源检索由 SmartRAG 提供。
- 默认部署：PostgreSQL（SQLite 仅开发模式）。

## 1. 技术基线（Ruby）
- [x] 确定 Ruby 版本：`3.2+`
- [x] 选型并固定 ORM：`sequel + pg`（或 ActiveRecord，二选一）
- [x] 测试框架：`rspec`
- [x] 契约与校验：`dry-struct` / `dry-validation`
- [x] HTTP 客户端：`faraday`（SmartRAG Adapter）
- [x] JSON：`oj`
- [x] 新增配置文件：`config/brain.yml`（映射 `docs/policies.md` 默认策略）

## 2. 目录与模块骨架
- [x] 建立目录：
  - `lib/smart_brain/event_store/`
  - `lib/smart_brain/memory_extractor/`
  - `lib/smart_brain/consolidator/`
  - `lib/smart_brain/retrieval_planner/`
  - `lib/smart_brain/retrievers/`
  - `lib/smart_brain/adapters/smart_rag/`
  - `lib/smart_brain/fusion/`
  - `lib/smart_brain/context_composer/`
  - `lib/smart_brain/model_provider/`
- [x] 建立测试目录：
  - `spec/commit_turn_spec.rb`
  - `spec/compose_context_spec.rb`
  - `spec/integration_smart_rag_adapter_spec.rb`

## 3. 数据库与迁移（Postgres）
- [x] 创建表：`sessions`
- [x] 创建表：`turns`
- [x] 创建表：`messages`
- [x] 创建表：`tool_calls`
- [x] 创建表：`refs`
- [x] 创建表：`memory_items`
- [x] 创建表：`memory_chunks`
- [x] 创建表：`entities`
- [x] 创建表：`entity_mentions`
- [x] 创建表：`summaries`（存 working_summary 与元信息）
- [x] 索引：`session_id/turn_id/updated_at/type+key/status`
- [x] FTS 索引：`messages`、`memory_chunks`

## 4. 里程碑 M1（第 1 周）：主链路打通
### 4.1 commit_turn
- [x] 实现 `SmartBrain.commit_turn(session_id:, turn_events:)`
- [x] EventStore 全量写入：turn/messages/tool_calls/refs
- [x] Retention Gate v0：
  - 必写：`tasks`、`decisions`、refs（事件层）
  - 条件写：`preferences`、`goals`、`events`
  - 不写长期记忆：闲聊、未确认推测
- [x] 冲突处理 v0：
  - 覆盖：`preferences/tasks` -> 旧值 `superseded`
  - 撤回：`retracted`

### 4.2 compose_context
- [x] 实现 `SmartBrain.compose_context(session_id:, user_message:, agent_state: {})`
- [x] 固定槽位装配 `ContextPackage`
- [x] 实现 `RetrievalPlanner` v0（exact/hybrid + 是否调用 SmartRAG）
- [x] 实现 SmartRAG Adapter：`retrieve(plan)` -> `EvidencePack`

### 4.3 M1 验收
- [x] `spec/commit_turn_spec.rb` 通过
- [x] `spec/compose_context_spec.rb` 通过
- [x] `context_id/request_id/plan_id` 全链路可追踪

## 5. 里程碑 M2（第 2 周）：策略落地与检索增强
### 5.1 policies 参数化
- [x] `retention.entity_gate.window_turns=20`
- [x] `retention.entity_gate.freq_threshold=2`
- [x] `confidence.user_asserted/tool_derived/inferred`
- [x] `retrieval.top_k=30`、`candidate_k=200`
- [x] `retrieval.query_expansion.enabled/max_queries`
- [x] `composition.token_limit/system_blocks_max_tokens/summary_max_tokens`
- [x] `composition.recent_turns_max/evidence_max_items/max_snippet_chars`
- [x] `composition.diversity.by_document/by_source_uri/memory_resource_ratio`

### 5.2 检索与融合
- [x] 对话侧 `ExactRetriever`（FTS）
- [x] 对话侧 `RelationalRetriever`（entities + mentions）
- [x] 多源去重：
  - resource: `document_id + section_id (+chunk_index)`
  - memory: `memory_item_id` 或 `turn_id + message_id`
- [x] 跨源统一重排接口（可先规则分，后接 reranker）

### 5.3 M2 验收
- [x] 资源检索触发条件符合 `docs/policies.md`
- [x] evidence 条数限制与截断生效
- [x] 多样性约束生效（同文档/同 source 限制）
- [x] `ignored_fields` 可记录后端不支持字段

## 6. 里程碑 M3（第 3 周）：摘要巩固与可观测
### 6.1 Consolidation
- [x] working_summary 触发条件：
  - `summarize_after_turns`
  - token 压力
  - 阶段事件（task 完成/decision 形成）
- [x] 摘要模板固定：
  - Goals
  - Decisions
  - Tasks
  - Key References
  - Open Questions
- [x] 保存摘要元信息：`summary_version/source_turn_range/generated_at`

### 6.2 Observability
- [x] `compose_context` 日志：
  - plan
  - evidence 入选与分数
  - token 预算与 trimmed 原因
  - ignored_fields
- [x] `commit_turn` 日志：
  - 写入 memory_items（type/key/confidence/status）
  - 冲突处理结果
  - 摘要触发情况

### 6.3 M3 验收
- [x] 满足 `docs/policies.md` 第 7 节最低验收标准
- [x] 单个 session 可回放并解释“为何写入/为何选中证据”

## 7. 测试与回归清单
- [x] 单元测试：gate/conflict/planner/budget/diversity/dedupe
- [x] 集成测试：SmartRAG adapter（成功、超时、字段降级）
- [x] 回归测试：固定会话数据集，比较 ContextPackage 关键字段稳定性
- [x] 性能指标：
  - `compose_context` P95
  - evidence 命中来源比例（memory/resource）
  - token 超预算率

## 8. 执行顺序（严格）
1. [x] 先做数据库迁移 + 契约对象（RetrievalPlan / EvidencePack / ContextPackage）
2. [x] 打通 `commit_turn` 最小闭环
3. [x] 打通 `compose_context` 最小闭环（含 SmartRAG adapter）
4. [x] 落地 `policies.md` 参数化
5. [x] 补齐 observability + 回归测试
6. [x] 再做检索增强与性能优化
