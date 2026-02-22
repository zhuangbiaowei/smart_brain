## 0. 总览：策略对象与生效点

SmartBrain 的主要运行时接口：
- `commit_turn(session_id, turn_events)`：写入真相（EventStore），抽取与巩固（MemoryStore）
- `compose_context(session_id, user_message, agent_state)`：检索与装配（ContextPackage）

策略分为四类：
1) **Retention（写入门控）**：在 `commit_turn` 生效  
2) **Consolidation（摘要/巩固）**：在 `commit_turn` 生效  
3) **Retrieval（检索策略）**：在 `compose_context` 生效  
4) **Composition（上下文装配策略）**：在 `compose_context` 生效

所有策略都必须满足：
- **可配置**：支持 brain.yml 覆盖默认值
- **可解释**：每次执行可输出 explain/ignored
- **可回归**：关键参数变化可对比输出差异（日志中保存 plan + context_id）

---

## 1. Retention Policy（写入门控）

### 1.1 原则
- **事件全收**：EventStore 记录每轮对话、工具调用、refs（文件/URL/产物）
- **长期记忆精炼**：MemoryStore 只存高价值、可复用、较稳定的信息
- **来源可追溯**：每条 memory_item 必须带 source_turn_id（可选 source_message_id）

### 1.2 记忆类型的写入优先级
按 `memory_types.md` 的 type：

**A. 必写（默认）**
- `tasks`：新增/更新/完成/阻塞（含状态流转）
- `decisions`：明确的决策/选择/承诺
- `refs`（事件层必写）：所有 file/url/artifact 引用
- `entities`：当满足“重要实体”条件（见 1.3）

**B. 条件写（默认）**
- `preferences`：明确偏好且具有稳定性/复用价值
- `goals`：明确长期目标或项目目标
- `events`：里程碑/异常/发布等高价值事件
- `cases/patterns`：当出现可复用结构（通常由工具/项目输出驱动）

**C. 不写入长期记忆（仅事件层）**
- 闲聊、情绪宣泄、一次性寒暄
- 纯推测、未确认事实
- 模型自我输出的“臆测偏好”（除非用户明确确认）

### 1.3 “重要实体”判定（Entity Gate）
实体进入 `entities`/`entity_mentions` 的条件（满足任一）：
- 出现频率：最近 `N_turns` 内出现 ≥ `freq_threshold`
- 明确指代：用户用“这个项目/那个仓库/上次那个链接”等指代并要求继续
- 结构性信号：出现在 URL、repo、文件路径、任务/决策中
- 用户声明：用户说“记住 X / 以后都按 X”

默认参数（可配置）：
- `N_turns = 20`
- `freq_threshold = 2`

### 1.4 稳定性与置信度（Confidence Policy）
每条 memory_item 写入时应计算 `confidence`（0..1），最低要求：
- 明确陈述（用户直接说）：≥ 0.8
- 由工具结果/结构化产物得出：≥ 0.9
- 由模型推断/总结得出：≤ 0.6（除非用户确认）

建议为每条 memory_item 记录：
- `confidence`
- `evidence_refs`（可选：指向 tool_calls 或 resources）

### 1.5 冲突与撤回（Conflict Policy）
- 覆盖型（overwrite）：`preferences/goals/tasks`
  - 新值写入后：旧值 `status=superseded`
- 多版本并存（versioned）：`decisions/events/cases/patterns`
  - 保留历史，标注 `made_at/updated_at`
- 撤回（retracted）：用户明确否认或修正
  - 将旧条目 `status=retracted`，并写入新事实（同 key 或新 key）

**冲突检测最低要求：**
- 同 `type+key` 新写入时，若 value 的关键字段变化显著，则视为冲突
- 冲突处理必须写入 explain（commit 输出）

---

## 2. Consolidation Policy（摘要与巩固）

### 2.1 两层摘要
- `working_summary`：滚动摘要（服务上下文装配，压缩历史）
- `core_memory`：稳定记忆块（system_blocks 的候选）

### 2.2 触发时机（Summarize Trigger）
默认触发（满足任一）：
- `turn_count_since_last_summary >= summarize_after_turns`（默认 12）
- 当前上下文估算 token 超过阈值（例如 70% budget）
- 检测到阶段性事件：task 完成、decision 形成、重大 tool 结果

### 2.3 摘要风格（Summary Style）
`working_summary` 建议格式固定，便于模型引用：

- 当前目标/任务状态
- 已确定的决策
- 关键实体与资源链接
- 未解决问题/下一步

示例结构（建议）：
- Goals:
- Decisions:
- Tasks:
- Key References:
- Open Questions:

### 2.4 摘要输入边界
摘要的输入来源应包含：
- 最近窗口对话（可包含更长窗口用于摘要生成）
- tool_calls 结果摘要（避免塞入原始大 JSON）
- refs（URL/file）元信息（标题/摘要）

摘要不应直接包含大段原文或长工具输出。

### 2.5 摘要的可追溯性
建议保存：
- `summary_version`
- `summary_source_turn_range`
- `summary_generated_at`
用于回放与调试。

---

## 3. Retrieval Policy（检索策略：SmartBrain + SmartRAG）

### 3.1 触发“资源检索”（SmartRAG）条件
SmartBrain 在 `compose_context` 时决定是否调用 SmartRAG。默认触发条件（满足任一）：
- 用户请求：查资料/对比方案/引用来源/“了解一下 X”
- 当前问题涉及外部事实或长文档内容（如标准、论文、仓库文档）
- refs 中存在相关 URL/file 且问题要求引用它们
- planner 判断需要 evidence 才能回答（intent=research/qa/debug）

默认关闭条件：
- 纯闲聊
- 仅与最近窗口强相关、无需外部资源

### 3.2 RetrievalPlan 生成默认值（v0.1）
默认启用模式：
- 对话侧：`exact + relational`（semantic 可选）
- 资源侧（SmartRAG）：`hybrid` 优先

默认 budget（可配置）：
- `top_k = 30`
- `candidate_k = 200`
- `per_mode_k`：exact 10 / semantic 10 / hybrid 30（资源侧）
- diversity：by_document 3 / by_source 10

### 3.3 Query Expansion（联想的可控实现）
联想只扩展检索，不生成事实。默认：
- 扩展 query 数量：3~8 条
- 扩展方式（任一/组合）：
  - 同义/别名（entity aliases）
  - 子主题（topic decomposition）
  - 关键词抽取（从 user_message 与 recent_turns）
- 每条扩展 query 权重 < 1.0（例如 0.5~0.8）

### 3.4 多源融合与统一重排（Cross-Source Rerank）
SmartBrain 推荐做“跨源统一 rerank”，即使 SmartRAG 内部已经 rerank：
- 输入：用户 query + 候选 snippets（memory + resource）
- 输出：统一 `rerank_score`，实现可比较排序

默认去重规则：
- resource：`document_id + section_id (+chunk_index)`
- memory：`memory_item_id` 或 `turn_id + message_id`

### 3.5 过滤策略（Filters）
默认建议：
- 若 user_message 明确指定范围（“在 smart_rag 里”）：`source_uri_prefix` 或 `document_ids`
- 若涉及近期进展：设置 `time_range`（资源侧看文档更新时间，对话侧看 turn 时间）
- 若多语言混杂：按语言过滤（可选）

执行方（SmartRAG）若不支持某过滤字段，必须在 EvidencePack.explain.ignored_fields 中声明。

---

## 4. Composition Policy（上下文装配：ContextPackage）

### 4.1 固定槽位（Slot-Based Composition）
装配顺序固定（强烈建议）：
1) `system_blocks`：core_profile / preferences / policies
2) `developer_blocks`：tooling/format rules（如需要）
3) `working_summary`
4) `recent_turns`（窗口）
5) `evidence`（来自 memory + resource）
6) `user_message`

### 4.2 Token 预算（Budgeting）
关键约束（可配置）：
- `token_limit`：例如 8k/16k（取决于你的本地模型上下文）
- `system_blocks_max_tokens`：例如 800
- `summary_max_tokens`：例如 600
- `recent_turns_max`：例如 8 轮
- `evidence_max_items`：例如 12
- `max_snippet_chars`：例如 800

优先级（从高到低）：
1) system_blocks
2) top evidence（高 rerank_score 且覆盖关键意图/实体）
3) working_summary
4) recent_turns
5) 长尾 evidence（联想扩展）

### 4.3 覆盖度（Coverage）
ContextComposer 必须保证：
- 至少包含 1 条覆盖当前问题核心实体/概念的 evidence（如果检索到）
- evidence 不应全部来自同一 document/source（受 diversity 约束）

### 4.4 多样性（Diversity）
默认：
- 同一 `document_id` 最多 3 条 evidence
- 同一 `source_uri` 最多 2 条
- memory/resource evidence 比例默认 40/60（可配置；若 memory 命中更高可自适应）

### 4.5 引用格式（Evidence Formatting）
为了让模型更可靠引用证据，建议把 evidence 注入时使用稳定格式：

- [E1] title — source_uri
  snippet…
  (mode=hybrid, score=0.88)

并在 debug 里保留：
- 哪些 evidence 被截断/丢弃及原因（budget/diversity）

---

## 5. 可观测与审计（Observability）

### 5.1 必要日志
每次 `compose_context` 建议记录：
- `context_id/session_id`
- RetrievalPlan（完整）
- evidence 选择结果（id + score + source）
- token 预算统计（limit/used/trimmed）
- ignored_fields（后端不支持）

每次 `commit_turn` 建议记录：
- 写入的 memory_items（type/key/confidence/status）
- 冲突处理结果（superseded/retracted）
- 摘要更新（是否触发、输入范围）

### 5.2 Debug 输出开关
开发期建议默认 `debug.trace=true`，上线后可配置关闭或仅保留采样。

---

## 6. 配置建议（brain.yml 对应）

示例配置映射（仅示意）：

```yaml
policies:
  retention:
    summarize_after_turns: 12
    entity_gate:
      window_turns: 20
      freq_threshold: 2
    confidence:
      user_asserted: 0.8
      tool_derived: 0.9
      inferred: 0.6

  retrieval:
    enable_resource_retrieval: auto
    top_k: 30
    candidate_k: 200
    query_expansion:
      enabled: true
      max_queries: 8

  composition:
    token_limit: 8192
    system_blocks_max_tokens: 800
    summary_max_tokens: 600
    recent_turns_max: 8
    evidence_max_items: 12
    max_snippet_chars: 800
    diversity:
      by_document: 3
      by_source_uri: 2
      memory_resource_ratio: "40/60"

  observability:
    trace: true
    store_plans: true
    store_contexts: true
```

---

## 7. 最低验收标准（v0.1）

* commit_turn：

  * EventStore 全量记录 turn/tool/refs
  * memory_items 写入门控生效（闲聊不进入长期记忆）
  * 冲突覆盖与撤回可工作（至少 preferences/tasks）

* compose_context：

  * 按槽位输出 ContextPackage
  * 资源检索按条件触发并能调用 SmartRAG.retrieve(plan)
  * 多样性与 token 预算可工作（至少 evidence 截断/条数限制）

* 可观测：

  * 至少保存 plan、evidence 选择、budget 统计与 ignored_fields
