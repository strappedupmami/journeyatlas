CREATE TABLE IF NOT EXISTS financial_accounts (
  account_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  provider TEXT NOT NULL,
  provider_account_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  institution_name TEXT,
  display_name TEXT,
  mask_last4 TEXT,
  sensitive_encrypted_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS financial_transactions (
  transaction_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  account_id TEXT NOT NULL,
  posted_at TEXT NOT NULL,
  pending INTEGER NOT NULL,
  sensitive_encrypted_json TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_financial_transactions_user_posted
ON financial_transactions (user_id, posted_at);

CREATE TABLE IF NOT EXISTS financial_provider_tokens (
  user_id TEXT NOT NULL,
  provider TEXT NOT NULL,
  sensitive_encrypted_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (user_id, provider)
);
