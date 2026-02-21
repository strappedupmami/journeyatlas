# Local Reasoner Training Report

- Generated at (UTC): 2026-02-21T07:22:42.280861+00:00
- Dataset: `kb/training/local_reasoner_training.jsonl`
- Samples: 98
- Synthetic augmentation samples: 35
- Labels: execution_now, health_recovery, resilience_safety, revenue_focus, strategy_long_horizon, technical_debug, travel_ops
- Vocabulary size: 512
- Max vocab configured: 512
- Min token frequency configured: 1
- Holdout accuracy: 60.00% (test size: 20)

## Holdout Label Breakdown

| Label | Correct | Total | Accuracy |
| --- | ---: | ---: | ---: |
| execution_now | 1 | 3 | 33.33% |
| health_recovery | 1 | 3 | 33.33% |
| resilience_safety | 1 | 3 | 33.33% |
| revenue_focus | 3 | 3 | 100.00% |
| strategy_long_horizon | 2 | 3 | 66.67% |
| technical_debug | 2 | 2 | 100.00% |
| travel_ops | 2 | 3 | 66.67% |

## Notes

- This model is optimized for low-latency on-device inference in Swift apps.
- Expand dataset coverage continuously; retrain after material product/policy updates.
- Use structured labels to keep execution suggestions predictable and safe.
