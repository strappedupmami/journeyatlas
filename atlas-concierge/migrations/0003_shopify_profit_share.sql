CREATE TABLE IF NOT EXISTS shopify_profit_share_reports (
  report_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  data_json TEXT NOT NULL
);
