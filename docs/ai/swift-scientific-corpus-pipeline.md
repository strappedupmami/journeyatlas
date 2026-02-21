# Swift AI Scientific Corpus Pipeline (Atlas/אטלס)

This pipeline powers the **Swift local AI** in:
- `/Users/avrohom/Downloads/journeyatlas/ios-app/AtlasMasaIOS`
- `/Users/avrohom/Downloads/journeyatlas/macos-app/AtlasMasaMacOS`

Goal: produce research-backed execution streams and tailored service recommendations.
Design lens: **Travel Design** (execution, journey ops, resilience, recovery, strategy, revenue, systems).

## What this pipeline builds

1. `AtlasResearchPack.swift` in both apps
2. science-derived local training rows
3. refreshed Swift travel-design model payloads
4. corpus coverage report

## Input corpus format (JSONL)

Each line:

```json
{"id":"goal-setting-2002","title":"Building a Practically Useful Theory of Goal Setting and Task Motivation","year":2002,"domain":"execution","actionable_insight":"Specific and challenging goals increase performance when feedback is present.","action_hint":"Convert broad intent into one measurable target for the next work block.","source_url":"https://doi.org/10.1037/0033-2909.128.3.705","keywords":["goals","execution","feedback"]}
```

Required practical fields:
- `title`
- `year`
- `domain`
- `actionable_insight`
- `action_hint`
- `source_url`
- `keywords`

## One-shot build

```bash
cd /Users/avrohom/Downloads/journeyatlas
./scripts/build_swift_research_corpus.py --input atlas-concierge/kb/training/scientific_papers_seed.jsonl --merge-into-base
./scripts/train_swift_travel_design_model.py
```

## Large-corpus fetch + build (OpenAlex)

```bash
cd /Users/avrohom/Downloads/journeyatlas
./scripts/fetch_openalex_atlas_papers.py \
  --query-file atlas-concierge/kb/training/openalex_atlas_queries.txt \
  --pages 20 \
  --per-page 100 \
  --max-papers 25000 \
  --from-year 1990 \
  --mailto you@example.com \
  --output atlas-concierge/kb/training/scientific_papers_openalex.jsonl

./scripts/build_swift_research_corpus.py \
  --input atlas-concierge/kb/training/scientific_papers_seed.jsonl atlas-concierge/kb/training/scientific_papers_openalex.jsonl \
  --max-papers 25000 \
  --merge-into-base

./scripts/train-local-model-loop.sh
./scripts/train_swift_travel_design_model.py
```

## Continuous refresh loop (day/night)

```bash
cd /Users/avrohom/Downloads/journeyatlas
RUN_FOREVER=1 \
INTERVAL_SECONDS=1800 \
FETCH_OPENALEX=1 \
OPENALEX_QUERY_FILE=atlas-concierge/kb/training/openalex_atlas_queries.txt \
OPENALEX_PAGES=20 \
OPENALEX_PER_PAGE=100 \
OPENALEX_MAX_PAPERS=25000 \
OPENALEX_FROM_YEAR=1990 \
OPENALEX_MAILTO=you@example.com \
MAX_PAPERS=25000 \
INPUT_CORPUS=atlas-concierge/kb/training/scientific_papers_seed.jsonl \
EXTRA_INPUT_CORPUS=atlas-concierge/kb/training/scientific_papers_openalex.jsonl \
./scripts/train-swift-science-loop.sh
```

## Enormous-corpus strategy (production)

Use a larger paper export from trusted sources, then point `INPUT_CORPUS` at it.
Recommended sources:
- PubMed / PubMed Central exports
- OpenAlex works dump
- Crossref metadata dumps

Filter to Atlas-relevant domains:
- productivity/execution science
- behavior change and habit formation
- sleep, cognition, stress recovery
- resilience/safety/continuity engineering
- finance behavior, savings, decision quality
- mobility/travel operations and transport safety
- novelty exposure + reflection loops for adaptive thinking
- neuroplasticity and cognitive reserve (slowing brain aging risk)

## Output files

- iOS research pack:
  - `/Users/avrohom/Downloads/journeyatlas/ios-app/AtlasMasaIOS/Sources/Core/AtlasResearchPack.swift`
- macOS research pack:
  - `/Users/avrohom/Downloads/journeyatlas/macos-app/AtlasMasaMacOS/Sources/Core/AtlasResearchPack.swift`
- generated science training rows:
  - `/Users/avrohom/Downloads/journeyatlas/atlas-concierge/kb/training/local_reasoner_training_science.jsonl`
- model report:
  - `/Users/avrohom/Downloads/journeyatlas/docs/ai/swift-travel-design-model-report.md`
- scientific corpus report:
  - `/Users/avrohom/Downloads/journeyatlas/docs/ai/swift-scientific-corpus-report.md`

## Notes

- This is for **Swift app local intelligence**, not cloud-only inference.
- This is for **Swift app local intelligence**, not the Rust cloud-pro tier.
- Keep source metadata so research-backed outputs can cite evidence.
- Do not ingest private user secrets or personal credentials into training corpora.
- If network/DNS is restricted in a given environment, fetch step can return zero papers; run the same command on a machine/network with internet access.
