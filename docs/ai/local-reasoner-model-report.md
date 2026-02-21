# Local Reasoner Training Report

- Generated at (UTC): 2026-02-21T07:39:46.177950+00:00
- Run ID: `20260221T073946Z`
- Dataset: `kb/training/local_reasoner_training.jsonl`
- Dataset SHA-256: `7fef9fe906f6fad64c54cdbd5205fd6f0aea0bee1e23b9d73e454f61e627423b`
- Samples: 98
- Synthetic augmentation samples: 35
- Labels: execution_now, health_recovery, resilience_safety, revenue_focus, strategy_long_horizon, technical_debug, travel_ops
- Vocabulary size: 512
- Max vocab configured: 512
- Min token frequency configured: 1
- Holdout accuracy: 85.71% (test size: 21)

- Holdout threshold: 55.00%
- Threshold pass: yes

## Holdout Label Breakdown

| Label | Correct | Total | Accuracy |
| --- | ---: | ---: | ---: |
| execution_now | 2 | 3 | 66.67% |
| health_recovery | 3 | 3 | 100.00% |
| resilience_safety | 2 | 3 | 66.67% |
| revenue_focus | 2 | 3 | 66.67% |
| strategy_long_horizon | 3 | 3 | 100.00% |
| technical_debug | 3 | 3 | 100.00% |
| travel_ops | 3 | 3 | 100.00% |

## Confusion Matrix (actual -> predicted counts)

- execution_now -> execution_now:2, resilience_safety:1
- health_recovery -> health_recovery:3
- resilience_safety -> resilience_safety:2, travel_ops:1
- revenue_focus -> revenue_focus:2, technical_debug:1
- strategy_long_horizon -> strategy_long_horizon:3
- technical_debug -> technical_debug:3
- travel_ops -> travel_ops:3

## Notes

- This model is optimized for low-latency on-device inference in Swift apps.
- Expand dataset coverage continuously; retrain after material product/policy updates.
- Use structured labels to keep execution suggestions predictable and safe.
