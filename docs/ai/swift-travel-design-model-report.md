# Swift Travel Design Model Report

- Generated at (UTC): 2026-02-21T11:31:46.037987+00:00
- Run ID: `20260221T113146Z`
- Dataset: `/Users/avrohom/Downloads/journeyatlas/atlas-concierge/kb/training/local_reasoner_training.jsonl`
- Dataset SHA-256: `b35597c0bb561b04247972b05acd57e61193b254fa0fccdb78e6fd4d3404a81c`
- Samples: 360
- Synthetic augmentation samples: 98
- Labels: travel_design_execution, travel_design_revenue, travel_design_resilience, travel_design_recovery, travel_design_strategy, travel_design_journey_ops, travel_design_systems
- Max vocab configured: 1000
- Min token frequency configured: 1
- Vocab before pruning: 1000
- Vocab after pruning: 800
- Prune target vocab: 800
- Holdout accuracy: 55.41% (test size: 74)

- Holdout threshold: 55.00%
- Threshold pass: yes

## Travel Design Taxonomy

- `travel_design_execution`: Travel design execution protocol
- `travel_design_revenue`: Travel design commercial growth lane
- `travel_design_resilience`: Travel design continuity and safety lane
- `travel_design_recovery`: Travel design recovery and regulation lane
- `travel_design_strategy`: Travel design long-horizon architecture lane
- `travel_design_journey_ops`: Travel design journey logistics lane
- `travel_design_systems`: Travel design systems diagnostics lane

## Holdout Label Breakdown

| Label | Correct | Total | Accuracy |
| --- | ---: | ---: | ---: |
| travel_design_execution | 15 | 16 | 93.75% |
| travel_design_revenue | 2 | 8 | 25.00% |
| travel_design_resilience | 3 | 8 | 37.50% |
| travel_design_recovery | 3 | 11 | 27.27% |
| travel_design_strategy | 10 | 15 | 66.67% |
| travel_design_journey_ops | 6 | 11 | 54.55% |
| travel_design_systems | 2 | 5 | 40.00% |

## Confusion Matrix (actual -> predicted counts)

- travel_design_execution -> travel_design_execution:15, travel_design_journey_ops:1
- travel_design_journey_ops -> travel_design_execution:1, travel_design_journey_ops:6, travel_design_strategy:4
- travel_design_recovery -> travel_design_execution:5, travel_design_recovery:3, travel_design_strategy:3
- travel_design_resilience -> travel_design_execution:1, travel_design_journey_ops:1, travel_design_resilience:3, travel_design_strategy:3
- travel_design_revenue -> travel_design_execution:3, travel_design_revenue:2, travel_design_strategy:3
- travel_design_strategy -> travel_design_execution:4, travel_design_recovery:1, travel_design_strategy:10
- travel_design_systems -> travel_design_execution:2, travel_design_strategy:1, travel_design_systems:2

## Notes

- This model is optimized for low-latency on-device Swift inference.
- Training pipeline is Swift-focused and independent from Rust cloud model lifecycle.
- Pruning is vocabulary-importance-based to reduce model size while retaining high-signal tokens.
