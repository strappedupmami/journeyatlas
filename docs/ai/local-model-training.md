# Atlas Masa Local Model Training (Apps)

This workflow trains the **on-device Swift local reasoning model** used by:
- `/Users/avrohom/Downloads/journeyatlas/ios-app/AtlasMasaIOS`
- `/Users/avrohom/Downloads/journeyatlas/macos-app/AtlasMasaMacOS`

It does not require cloud compute and is designed for fast iteration.

## 1) Training dataset

Primary dataset file:
- `/Users/avrohom/Downloads/journeyatlas/atlas-concierge/kb/training/local_reasoner_training.jsonl`

JSONL schema (one object per line):

```json
{"prompt":"Need immediate execution now.","label":"execution_now","next_action":"Execute one high-impact step in the next 15 minutes, then lock the next checkpoint."}
```

Required fields:
- `prompt`
- `label`

Optional:
- `next_action`

Current supported labels:
- `execution_now`
- `revenue_focus`
- `resilience_safety`
- `health_recovery`
- `technical_debug`
- `strategy_long_horizon`
- `travel_ops`

## 2) Run training once

```bash
cd /Users/avrohom/Downloads/journeyatlas
./scripts/train-local-model-loop.sh
```

This command will:
- train a lightweight local classifier in Rust
- regenerate model payload block in:
  - `/Users/avrohom/Downloads/journeyatlas/ios-app/AtlasMasaIOS/Sources/Core/LocalReasoningEngine.swift`
  - `/Users/avrohom/Downloads/journeyatlas/macos-app/AtlasMasaMacOS/Sources/Core/LocalReasoningEngine.swift`
- write a report at:
  - `/Users/avrohom/Downloads/journeyatlas/docs/ai/local-reasoner-model-report.md`

## 3) Run continuously (day/night)

```bash
cd /Users/avrohom/Downloads/journeyatlas
RUN_FOREVER=1 INTERVAL_SECONDS=1800 ./scripts/train-local-model-loop.sh
```

- `RUN_FOREVER=1` keeps retraining in a loop
- `INTERVAL_SECONDS=1800` retrains every 30 minutes

Use `tmux`/`screen` if you want this to survive terminal closure.

## 4) Quality gate

Check holdout accuracy in:
- `/Users/avrohom/Downloads/journeyatlas/docs/ai/local-reasoner-model-report.md`

If accuracy drops, add better labeled prompts before shipping.

## 5) Feeding more Atlas data safely

Add only user-approved, non-secret data into the JSONL dataset.
Never add credentials, private tokens, or raw third-party personal data.

Recommended data sources for this local model:
- anonymized prompt/response feedback snippets
- execution-loop notes (daily/mid/long horizon)
- mobility/travel ops prompts
- reliability/safety incidents and recovery prompts

