# Swift Travel Design Model Report

- Generated at (UTC): 2026-02-21T17:54:10.320590+00:00
- Run ID: `20260221T175410Z-emergency-crisis-v2`
- Run tag: `emergency-crisis-v2`
- Dataset: `/Users/avrohom/Downloads/journeyatlas/atlas-concierge/kb/training/local_reasoner_training.jsonl`
- Dataset SHA-256: `3440818d78a44b96bf7b41684b23b3a579b389fdd50fb13d2e85e9535bc51eff`
- Samples: 541
- Synthetic augmentation samples: 137
- Labels: travel_design_execution, travel_design_revenue, travel_design_resilience, travel_design_recovery, travel_design_strategy, travel_design_journey_ops, travel_design_systems, travel_design_emergency_command, travel_design_human_problem_solving, travel_design_tech_innovation
- Max vocab configured: 1000
- Min token frequency configured: 1
- Vocab before pruning: 1000
- Vocab after pruning: 800
- Prune target vocab: 800
- Prior uniform mix: 0.65
- Holdout accuracy: 56.25% (test size: 112)

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
- `travel_design_emergency_command`: Travel design emergency command lane
- `travel_design_human_problem_solving`: Travel design human problem-solving optimization lane
- `travel_design_tech_innovation`: Travel design technology innovation systems lane

## Holdout Label Breakdown

| Label | Correct | Total | Accuracy |
| --- | ---: | ---: | ---: |
| travel_design_execution | 13 | 15 | 86.67% |
| travel_design_revenue | 3 | 10 | 30.00% |
| travel_design_resilience | 3 | 10 | 30.00% |
| travel_design_recovery | 1 | 11 | 9.09% |
| travel_design_strategy | 8 | 15 | 53.33% |
| travel_design_journey_ops | 5 | 11 | 45.45% |
| travel_design_systems | 9 | 10 | 90.00% |
| travel_design_emergency_command | 8 | 10 | 80.00% |
| travel_design_human_problem_solving | 6 | 10 | 60.00% |
| travel_design_tech_innovation | 7 | 10 | 70.00% |

## Confusion Matrix (actual -> predicted counts)

- travel_design_emergency_command -> travel_design_emergency_command:8, travel_design_execution:2
- travel_design_execution -> travel_design_execution:13, travel_design_journey_ops:1, travel_design_systems:1
- travel_design_human_problem_solving -> travel_design_execution:2, travel_design_human_problem_solving:6, travel_design_recovery:1, travel_design_strategy:1
- travel_design_journey_ops -> travel_design_execution:1, travel_design_journey_ops:5, travel_design_strategy:5
- travel_design_recovery -> travel_design_execution:6, travel_design_recovery:1, travel_design_resilience:1, travel_design_strategy:2, travel_design_systems:1
- travel_design_resilience -> travel_design_emergency_command:1, travel_design_execution:2, travel_design_journey_ops:3, travel_design_resilience:3, travel_design_systems:1
- travel_design_revenue -> travel_design_execution:5, travel_design_revenue:3, travel_design_strategy:2
- travel_design_strategy -> travel_design_execution:3, travel_design_journey_ops:3, travel_design_recovery:1, travel_design_strategy:8
- travel_design_systems -> travel_design_journey_ops:1, travel_design_systems:9
- travel_design_tech_innovation -> travel_design_execution:1, travel_design_journey_ops:1, travel_design_strategy:1, travel_design_tech_innovation:7

## Notes

- This model is optimized for low-latency on-device Swift inference.
- Training pipeline is Swift-focused and independent from Rust cloud model lifecycle.
- Pruning is vocabulary-importance-based to reduce model size while retaining high-signal tokens.
