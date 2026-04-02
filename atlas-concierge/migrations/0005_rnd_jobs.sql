CREATE TABLE IF NOT EXISTS rnd_jobs (
  job_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  data_json TEXT NOT NULL
);
