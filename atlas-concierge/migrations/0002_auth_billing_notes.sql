CREATE TABLE IF NOT EXISTS auth_users (
  user_id TEXT PRIMARY KEY,
  provider TEXT NOT NULL,
  email TEXT NOT NULL,
  name TEXT NOT NULL,
  locale TEXT NOT NULL,
  trip_style TEXT,
  risk_preference TEXT,
  memory_opt_in INTEGER NOT NULL,
  passkey_user_handle TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS auth_sessions (
  session_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS studio_preferences (
  user_id TEXT PRIMARY KEY,
  data_json TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS survey_states (
  user_id TEXT PRIMARY KEY,
  data_json TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS feedback_items (
  feedback_id TEXT PRIMARY KEY,
  data_json TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS user_notes (
  note_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  data_json TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS passkeys (
  passkey_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  data_json TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS billing_subscriptions (
  user_id TEXT PRIMARY KEY,
  stripe_customer_id TEXT,
  stripe_subscription_id TEXT,
  status TEXT NOT NULL,
  current_period_end TEXT,
  updated_at TEXT NOT NULL
);
