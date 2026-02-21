# Swift Scientific Corpus Build Report

- Generated at (UTC): 2026-02-21T17:49:21.849840+00:00
- Scientific papers loaded: 46
- Research-derived training rows generated: 161
- Rows merged into base local_reasoner_training.jsonl: 42
- Existing rows updated in base local_reasoner_training.jsonl: 20
- Base local_reasoner_training.jsonl total rows: 304

## Domain coverage

| Domain | Count |
| --- | ---: |
| biological-performance | 1 |
| crisis-management | 1 |
| decision-quality | 3 |
| digital-innovation | 1 |
| emergency-preparedness | 1 |
| emergency-response | 1 |
| environmental-performance | 1 |
| execution | 5 |
| health | 1 |
| human-performance | 1 |
| human-problem-solving | 1 |
| incident-command | 1 |
| motivation | 1 |
| operations | 3 |
| physical-innovation | 1 |
| planning | 1 |
| problem-solving | 1 |
| productivity | 4 |
| recovery | 3 |
| resilience | 2 |
| safety | 1 |
| skill-building | 2 |
| systems-innovation | 1 |
| team-ops | 1 |
| technology-innovation | 1 |
| travel | 2 |
| wealth | 3 |
| wellbeing | 1 |

## Label mapping coverage

| Label | Count |
| --- | ---: |
| travel_design_emergency_command | 4 |
| travel_design_execution | 9 |
| travel_design_human_problem_solving | 5 |
| travel_design_journey_ops | 5 |
| travel_design_recovery | 5 |
| travel_design_resilience | 3 |
| travel_design_revenue | 3 |
| travel_design_strategy | 8 |
| travel_design_tech_innovation | 4 |

## Outputs

- iOS research pack: `/Users/avrohom/Downloads/journeyatlas/ios-app/AtlasMasaIOS/Sources/Core/AtlasResearchPack.swift`
- macOS research pack: `/Users/avrohom/Downloads/journeyatlas/macos-app/AtlasMasaMacOS/Sources/Core/AtlasResearchPack.swift`
- generated science training rows: `/Users/avrohom/Downloads/journeyatlas/atlas-concierge/kb/training/local_reasoner_training_science.jsonl`
- report: `/Users/avrohom/Downloads/journeyatlas/docs/ai/swift-scientific-corpus-report.md`

## Next step

Run local training to update Swift model payloads:

```bash
cd /Users/avrohom/Downloads/journeyatlas
./scripts/train-local-model-loop.sh
```
