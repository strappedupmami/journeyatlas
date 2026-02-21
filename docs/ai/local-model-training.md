# Atlas/אטלס Swift Travel Design Model Training

This workflow trains the **on-device Swift local reasoning model** used by:
- `/Users/avrohom/Downloads/journeyatlas/ios-app/AtlasMasaIOS`
- `/Users/avrohom/Downloads/journeyatlas/macos-app/AtlasMasaMacOS`

It is **Swift-app focused** and independent from the Rust cloud-pro model lifecycle.

## 1) Training dataset

Primary dataset file:
- `/Users/avrohom/Downloads/journeyatlas/atlas-concierge/kb/training/local_reasoner_training.jsonl`

JSONL schema (one object per line):

```json
{"prompt":"Travel design brief: I need immediate execution with one controlled output block.","label":"travel_design_execution","next_action":"Design one 15-minute field move now, execute it, and log the outcome."}
```

Required fields:
- `prompt`
- `label`

Optional:
- `next_action`

Travel Design taxonomy labels:
- `travel_design_execution`
- `travel_design_revenue`
- `travel_design_resilience`
- `travel_design_recovery`
- `travel_design_strategy`
- `travel_design_journey_ops`
- `travel_design_systems`

Legacy labels are auto-mapped during training.

## Hebrew + Israeli language expertise

The Swift trainer now includes:
- Hebrew-aware tokenization (not English-only)
- academic Hebrew vocabulary in every travel-design lane
- Israeli usage-context synthetic prompts (operational Hebrew, not literal translation only)

This improves classification and output quality for:
- Hebrew prompts
- mixed Hebrew/English prompts
- Israel-specific operational phrasing

## 2) Run training once

```bash
cd /Users/avrohom/Downloads/journeyatlas
./scripts/train-local-model-loop.sh
```

This command will:
- train a lightweight local classifier via Python tooling for Swift app injection
- regenerate model payload block in:
  - `/Users/avrohom/Downloads/journeyatlas/ios-app/AtlasMasaIOS/Sources/Core/LocalReasoningEngine.swift`
  - `/Users/avrohom/Downloads/journeyatlas/macos-app/AtlasMasaMacOS/Sources/Core/LocalReasoningEngine.swift`
- write a report at:
  - `/Users/avrohom/Downloads/journeyatlas/docs/ai/swift-travel-design-model-report.md`
  - compatibility copy: `/Users/avrohom/Downloads/journeyatlas/docs/ai/local-reasoner-model-report.md`
- write versioned artifacts at:
  - `/Users/avrohom/Downloads/journeyatlas/artifacts/swift-travel-design-model/<run_id>/`
  - plus `/Users/avrohom/Downloads/journeyatlas/artifacts/swift-travel-design-model/latest.json`

## 2.1) Pruning controls

The trainer performs token-importance pruning by default.

- `MAX_VOCAB` controls pre-prune vocabulary build (default `1000`)
- `PRUNE_TARGET_VOCAB` controls final model vocab budget (default `800`)

Example:

```bash
cd /Users/avrohom/Downloads/journeyatlas
MAX_VOCAB=1800 PRUNE_TARGET_VOCAB=640 ./scripts/train-local-model-loop.sh
```

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
- `/Users/avrohom/Downloads/journeyatlas/docs/ai/swift-travel-design-model-report.md`

If accuracy drops, add better labeled prompts before shipping.

### Scientific corpus mode for Swift apps

To build research-grounded Swift outputs from scientific papers:

```bash
cd /Users/avrohom/Downloads/journeyatlas
./scripts/build_swift_research_corpus.py --input atlas-concierge/kb/training/scientific_papers_seed.jsonl --merge-into-base
./scripts/train-local-model-loop.sh
```

For continuous refresh:

```bash
cd /Users/avrohom/Downloads/journeyatlas
RUN_FOREVER=1 INTERVAL_SECONDS=1800 ./scripts/train-swift-science-loop.sh
```

Pipeline details:
- `/Users/avrohom/Downloads/journeyatlas/docs/ai/swift-scientific-corpus-pipeline.md`

Default quality gate:
- minimum holdout accuracy: `55%`
- if below threshold, run artifacts are still produced, but Swift model injection is blocked.

Override only if explicitly needed:

```bash
cd /Users/avrohom/Downloads/journeyatlas
ALLOW_BELOW_THRESHOLD=1 ./scripts/train-local-model-loop.sh
```

## 5) Feeding more Atlas data safely

Add only user-approved, non-secret data into the JSONL dataset.
Never add credentials, private tokens, or raw third-party personal data.

Recommended data sources for this Swift travel-design model:
- anonymized prompt/response feedback snippets
- execution-loop notes (daily/mid/long horizon)
- mobility/travel ops prompts
- reliability/safety incidents and recovery prompts
- novelty + reflection prompts that help users reframe problems from new angles
- cognitive aging slowdown patterns (cognitive reserve, recovery sleep, safe exploration)
