## 1. 目的

ContextPackage 用于把“本轮给模型的上下文”表达为结构化对象，解决：
- 直接拼接全部 history 不可扩展（token 预算）
- 证据与对话混在一起不可控（难 debug）
- 工具结果与长期记忆无法一致治理（无统一入口）

ContextPackage 是 **SmartBrain 的输出**，SmartBrain 对其内容负责；SmartPrompt 只负责把它转换为模型调用格式并发送。

---

## 2. 顶层结构

```json
{
  "version": "0.1",
  "context_id": "uuid",
  "session_id": "string",
  "created_at": "2026-02-20T12:00:00Z",

  "system_blocks": [],
  "developer_blocks": [],
  "working_summary": "",
  "recent_turns": [],
  "evidence": [],
  "user_message": { "role": "user", "content": "..." },

  "constraints": {},
  "debug": {}
}
```

字段说明：

* `version`：协议版本（必填）
* `context_id`：本次装配唯一 id（建议必填）
* `session_id`：会话 id（必填）
* `created_at`：生成时间（必填）
* `system_blocks`：可钉在 system 的核心记忆与规则
* `developer_blocks`：开发者侧指令（工具使用规则、引用规则等）
* `working_summary`：滚动摘要（可选）
* `recent_turns`：最近窗口对话（可选）
* `evidence`：检索证据（可选但关键）
* `user_message`：本轮用户输入（必填）
* `constraints`：token 预算/多样性等约束的“结果”或“输入”（可选）
* `debug`：解释信息（可选）

---

## 3. system_blocks

用于承载稳定信息，通常来自 SmartBrain 的 MemoryExtractor/Consolidator。

```json
{
  "type": "core_profile|preferences|goals|policies|other",
  "text": "string",
  "updated_at": "2026-02-20T00:00:00Z",
  "source": { "turn_id": "...", "memory_item_id": "..." }
}
```

建议约定：

* `core_profile`：用户身份/背景（稳定）
* `preferences`：偏好与约束（稳定但会更新）
* `goals`：长期目标/项目目标
* `policies`：系统规则（如引用要求、工具调用规范）

---

## 4. developer_blocks（可选）

用于放置“执行层规则”，例如：

* 必须引用证据回答
* 工具调用失败时如何降级
* 输出格式要求

结构同 system_blocks，type 可为：`tooling_rules|format_rules|safety_rules|other`

---

## 5. working_summary（可选）

* 目的：压缩较早对话
* 内容：一段文字（可带 bullet）
* 由 SmartBrain 维护，SmartPrompt 不应擅自修改

---

## 6. recent_turns（可选）

```json
[
  { "role": "user", "content": "..." },
  { "role": "assistant", "content": "..." }
]
```

约束建议：

* 只保留最近 N 轮（由 brain.yml 的 retention.window_turns 控制）
* 不应包含过长的 tool result（tool result 应进入 evidence 或另一个结构）

---

## 7. evidence（关键）

Evidence 是 SmartBrain 从多个来源收集并筛选后的“可引用证据”，通常来自：

* SmartBrain 自己的 memory store（对话记忆、任务状态、实体事件）
* SmartRAG 的资源检索（文档/URL 知识库）

### 7.1 EvidenceItem 结构

```json
{
  "id": "string",
  "source": "memory|resource",
  "source_uri": "string",
  "title": "string",
  "snippet": "string",
  "mode": "exact|semantic|hybrid|relational|associative",
  "score": 0.0,
  "signals": {
    "rerank_score": 0.0,
    "rrf_score": 0.0,
    "vector_score": 0.0,
    "fts_score": 0.0
  },
  "provenance": {
    "request_id": "uuid",
    "plan_version": "0.1",
    "retrieved_at": "2026-02-20T12:00:00Z"
  },
  "ref": {
    "document_id": "...",
    "section_id": "...",
    "turn_id": "...",
    "memory_item_id": "..."
  }
}
```

字段说明：

* `source_uri`：必须能定位回源（URL、file://、viking://、smartbrain://turn/...）
* `snippet`：默认短文本，可用于直接拼入 prompt
* `signals`：可选，用于 debug 与可解释
* `ref`：可选，内部定位

### 7.2 Evidence 分组（可选）

SmartBrain 可以在 evidence 上附加 `group` 字段（例如 `exact_hits` / `semantic_hits` / `relational_bundle`），但 v0.1 不强制。

---

## 8. user_message（必填）

```json
{ "role": "user", "content": "..." }
```

> SmartBot/SmartPrompt 使用该字段作为最终 user message，而不是从 recent_turns 推断。

---

## 9. constraints（可选）

用于携带“预算输入/装配结果”，便于观测与回归。

```json
{
  "token_budget": { "limit": 8000, "used_estimate": 6120 },
  "diversity": { "by_document": 3, "by_source": 10 },
  "truncation": { "snippets_max_chars": 800, "recent_turns_max": 8 }
}
```

---

## 10. debug（可选但强烈建议开发期启用）

```json
{
  "planner": { "intent": "qa", "reason": "user asked for ...", "queries": ["..."] },
  "why_selected": [
    "evidence#5 rerank_score=0.91, covers key entity X",
    "recent_turns kept because user said 'as we discussed earlier'"
  ],
  "ignored": [
    "filter time_range not supported by backend, skipped",
    "diversity.by_source not supported, skipped"
  ]
}
```

---

## 11. SmartPrompt 消息转换建议（非规范，但推荐）

SmartBot/SmartPrompt 将 ContextPackage 转成 messages 的顺序建议：

1. system：拼接所有 `system_blocks.text`（可加标题分隔）
2. developer：拼接 `developer_blocks.text`（如果你的 runtime 支持 developer role，否则并入 system）
3. system/assistant：插入 `working_summary`（建议以“Summary:”前缀）
4. history：插入 `recent_turns`
5. assistant/system：插入 `evidence`（建议以“Evidence:”结构化列出）
6. user：`user_message`

> 重要：证据与摘要应当以稳定格式注入，便于模型引用与后续评估。

---

## 12. 变更策略

* v0.1：新增字段只能“可选”，不得破坏现有字段含义
* 执行方必须忽略未知字段（向后兼容）
* 如需破坏性变更，另起 major 版本并提供迁移说明