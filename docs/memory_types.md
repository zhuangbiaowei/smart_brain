## 1. 目的

MemoryTypes 用于把“对话与工具事件中可沉淀的长期信息”结构化，解决：
- 记忆污染（把闲聊当长期事实）
- 冲突不可控（同一事实多版本）
- 检索不可用（只存全文，无法聚合/过滤/关联）
- 无法解释（不知道这条记忆来自哪里）

本规范定义：
- 记忆类型（type）
- key 规则（如何唯一标识一条记忆）
- value 形态（建议的 JSON）
- 写入门控与冲突合并策略（最低要求）

---

## 2. 总体存储模型（建议）

### 2.1 memory_items（结构化）
字段建议：
- `id`
- `type`
- `key`
- `value_json`
- `confidence`（0..1）
- `status`（active|superseded|retracted）
- `source_turn_id`
- `source_message_id`（可选）
- `evidence_refs`（可选：document_id/section_id/url）
- `updated_at`

### 2.2 memory_chunks（可检索文本）
- `id`
- `memory_item_id`
- `text`（用于 FTS/embedding）
- `embedding`
- `tsv`
- `meta_json`（包含 type/key、版本、语言等）

> 规则：memory_items 是真相；memory_chunks 是派生索引内容，可重建。

---

## 3. 类型清单（v0.1）

v0.1 约定以下类型（type）：

### 3.1 profile（用户/主体画像）
- 含义：稳定身份信息（职业、背景、组织、长期角色）
- key 规则：`profile:<subject>`  
  - subject 常用：`user`（默认）、或 `agent`（多主体时）
- value_json 示例：
```json
{
  "subject": "user",
  "facts": [
    {"k": "role", "v": "Executive Secretary General of ...", "since": "2024-05-17"}
  ]
}
```

* 写入门控：只有明确陈述且稳定的信息才写入；不确定内容写入 events，不写 profile。

### 3.2 preferences（偏好与约束）

* 含义：写作风格、工具偏好、语言偏好、预算偏好等
* key 规则：`pref:<scope>:<name>`

  * scope：`writing|coding|tools|ui|other`
* value_json 示例：

```json
{
  "scope": "writing",
  "name": "tone",
  "value": "focused and exacting",
  "priority": 0.8
}
```

* 冲突策略：同 key 新值覆盖旧值（旧值 status=superseded），保留历史版本。

### 3.3 goals（长期目标）

* 含义：项目目标、学习目标、长期规划
* key 规则：`goal:<project_or_topic>:<name>`
* value_json 示例：

```json
{
  "project": "SmartBrain",
  "name": "local_first_memory_runtime",
  "description": "Build ...",
  "status": "active"
}
```

### 3.4 tasks（任务与待办）

* 含义：可追踪的任务项（含状态流转）
* key 规则：`task:<project>:<task_id>`（task_id 可为 uuid 或 slug）
* value_json 示例：

```json
{
  "project": "SmartBot",
  "task_id": "brain_runtime_mvp",
  "title": "Integrate SmartBrain into SmartBot loop",
  "status": "todo|doing|done|blocked",
  "due": "2026-03-01",
  "notes": ["..."]
}
```

* 重要：tasks 应当支持状态更新（commit_turn 时识别“已完成/阻塞”）。

### 3.5 decisions（决策与承诺）

* 含义：已经决定的方案、选择、不可逆约束
* key 规则：`decision:<project>:<topic>`
* value_json 示例：

```json
{
  "project": "SmartRAG",
  "topic": "retrieve_api_contract",
  "decision": "Add retrieve(plan) returning EvidencePack",
  "rationale": "Contract-based integration with SmartBrain",
  "made_at": "2026-02-20"
}
```

### 3.6 entities（实体）

* 含义：对话中出现的重要实体（人/组织/项目/仓库/文件/URL 域名等）
* key 规则：`entity:<kind>:<canonical>`

  * kind：`person|org|repo|file|url|topic|other`
* value_json 示例：

```json
{
  "kind": "repo",
  "canonical": "zhuangbiaowei/smart_rag",
  "aliases": ["smart_rag"],
  "attrs": {"host": "github.com"}
}
```

* 备注：entities 通常配合 entity_mentions 表用于关联检索。

### 3.7 events（重要事件）

* 含义：可被未来引用的关键事件（发布、会议、里程碑、异常）
* key 规则：`event:<project_or_scope>:<date>:<slug>`
* value_json 示例：

```json
{
  "scope": "SmartBrain",
  "date": "2026-02-20",
  "title": "Decided to split memory runtime into SmartBrain",
  "impact": "architecture"
}
```

### 3.8 cases（案例/经验片段）

* 含义：某次任务的输入—过程—输出—结果，可复用
* key 规则：`case:<domain>:<slug_or_id>`
* value_json 示例：

```json
{
  "domain": "rag_debug",
  "problem": "...",
  "solution": "...",
  "outcome": "works",
  "artifacts": [{"type":"doc","ref":"..."}]
}
```

### 3.9 patterns（模式/规则）

* 含义：从多个案例/对话中归纳出的可复用策略
* key 规则：`pattern:<domain>:<name>`
* value_json 示例：

```json
{
  "domain": "context_composing",
  "name": "slot_based_composition",
  "rule": "system core -> summary -> recent -> evidence -> user",
  "confidence": 0.7
}
```

---

## 4. key 设计规则（必须遵守）

1. **稳定性**：同一事实应映射到同一 key（便于更新与去重）
2. **可读性**：key 应可读可排查（不全是 uuid）
3. **可扩展**：允许引入 scope/domain/project 前缀
4. **可多主体**：必要时将 subject 纳入 key（profile/user vs profile/agent）

---

## 5. 写入门控（Retention Gate）最低要求

SmartBrain 在 commit_turn 时必须执行门控：

* 必写（高价值）：

  * tool_call 结果（尤其是产出 artifact、变更状态）
  * refs（文件/URL）及其摘要/元信息
  * decisions（明确决策）
  * tasks（新增/更新/完成）
* 条件写（中价值）：

  * preferences（明确偏好、可稳定复用）
  * goals（明确长期目标）
  * entities/events（出现频繁或被强调的实体/事件）
* 不写入长期记忆（仅存 event）：

  * 闲聊、情绪性内容、一次性无复用信息
  * 模糊推测、未确认事实

---

## 6. 冲突合并策略（最低要求）

### 6.1 覆盖型（overwrite）

适用：preferences/goals/tasks（同 key 新值应覆盖旧值）

* 旧值标记：`status = superseded`
* 保留历史版本（便于回滚/审计）

### 6.2 多版本并存（versioned）

适用：profile（谨慎）、decisions/events（应保留历史）

* 以时间或版本号区分（在 value_json 中存 `version` 或 `made_at`）
* compose 时默认选最新/最高置信

### 6.3 撤回（retracted）

适用：用户明确否认的事实

* 将旧条目标记 `status = retracted`
* 新条目可写入修正事实（同 key 或新 key）

---

## 7. memory_chunks 文本化规则（用于检索）

为了让 FTS/embedding 有用，每个 memory_item 应生成一个或多个 chunk 文本：

* 第一行：`[type:key]`（用于定位）
* 主体：对 value_json 的可读摘要
* 可附：来源/时间/项目

示例（preferences）：

```
[preferences:pref:writing:tone]
User prefers a focused and exacting tone for technical documents.
Updated at: 2026-02-20
```

---

## 8. 版本与兼容

* v0.1：类型集合与 key 规则为最低一致性要求
* 可新增 type，但必须遵守 key 规则
* 破坏性变更（重命名 type/key 规则）需要 major 版本与迁移策略