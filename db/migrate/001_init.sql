-- SmartBrain v0.1 initial schema (PostgreSQL)

CREATE TABLE IF NOT EXISTS sessions (
  id TEXT PRIMARY KEY,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS turns (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL REFERENCES sessions(id),
  seq INTEGER NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY,
  turn_id TEXT NOT NULL REFERENCES turns(id),
  role TEXT NOT NULL,
  content TEXT NOT NULL,
  model TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  meta_json JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS tool_calls (
  id TEXT PRIMARY KEY,
  turn_id TEXT NOT NULL REFERENCES turns(id),
  name TEXT NOT NULL,
  args_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  result_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  status TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS refs (
  id TEXT PRIMARY KEY,
  turn_id TEXT NOT NULL REFERENCES turns(id),
  ref_type TEXT NOT NULL,
  ref_uri TEXT NOT NULL,
  ref_meta_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS memory_items (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  type TEXT NOT NULL,
  key TEXT NOT NULL,
  value_json JSONB NOT NULL,
  confidence NUMERIC(3,2) NOT NULL DEFAULT 0.6,
  status TEXT NOT NULL DEFAULT 'active',
  source_turn_id TEXT,
  source_message_id TEXT,
  evidence_refs JSONB NOT NULL DEFAULT '[]'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS memory_chunks (
  id TEXT PRIMARY KEY,
  memory_item_id TEXT NOT NULL REFERENCES memory_items(id),
  text TEXT NOT NULL,
  tsv TSVECTOR,
  meta_json JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS entities (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  kind TEXT NOT NULL,
  canonical_id TEXT
);

CREATE TABLE IF NOT EXISTS entity_mentions (
  id TEXT PRIMARY KEY,
  entity_id TEXT NOT NULL REFERENCES entities(id),
  turn_id TEXT,
  message_id TEXT,
  span_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS summaries (
  session_id TEXT PRIMARY KEY,
  summary_text TEXT NOT NULL,
  summary_version INTEGER NOT NULL DEFAULT 1,
  summary_source_turn_range JSONB NOT NULL DEFAULT '{}'::jsonb,
  summary_generated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_turns_session_seq ON turns(session_id, seq);
CREATE INDEX IF NOT EXISTS idx_memory_items_session_status ON memory_items(session_id, status);
CREATE INDEX IF NOT EXISTS idx_memory_items_type_key ON memory_items(type, key);
CREATE INDEX IF NOT EXISTS idx_messages_turn_id ON messages(turn_id);
CREATE INDEX IF NOT EXISTS idx_refs_turn_id ON refs(turn_id);
CREATE INDEX IF NOT EXISTS idx_entity_mentions_entity_id ON entity_mentions(entity_id);

CREATE INDEX IF NOT EXISTS idx_memory_chunks_tsv ON memory_chunks USING GIN (tsv);
