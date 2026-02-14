CREATE TABLE IF NOT EXISTS sessions (
  session_id TEXT PRIMARY KEY,
  user_id TEXT,
  locale TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  turns_json TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS inventory_items (
  sku TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  quantity INTEGER NOT NULL,
  minimum_required INTEGER NOT NULL
);
