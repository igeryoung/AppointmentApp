# Charge Item Latency Benchmark

Date: March 25, 2026

Scope: Measure create/edit charge-item latency before and after moving UI updates off the synchronous server-write path.

Benchmark file:

- `test/app/benchmarks/charge_item_latency_benchmark_test.dart`

Method:

- Controlled benchmark with synthetic server delay.
- Legacy path model: local write, synchronous server sync, local reconcile, full reload before return.
- New path model: local write plus immediate state update, background server sync after return.
- Configured synthetic delay:
  - server save: 40 ms
- Samples per scenario: 12 after warmup.

## Results

### User-visible latency

| Scenario | Before avg | After avg | Improvement |
|---|---:|---:|---:|
| Add charge item | 48.22 ms | 3.10 ms | 45.12 ms |
| Edit charge item | 46.72 ms | 1.57 ms | 45.15 ms |

### Pipeline stage averages

| Scenario | Local write | Server sync | Reload | Background sync | Total completion |
|---|---:|---:|---:|---:|---:|
| Add before | 2.09 ms | 45.79 ms | 0.33 ms | 0.00 ms | 48.22 ms |
| Add after | 3.10 ms | 0.00 ms | 0.00 ms | 45.80 ms | 48.90 ms |
| Edit before | 0.90 ms | 45.51 ms | 0.30 ms | 0.00 ms | 46.72 ms |
| Edit after | 1.57 ms | 0.00 ms | 0.00 ms | 47.55 ms | 49.12 ms |

Detailed output captured from the benchmark run:

```json
{
  "benchmark": "charge_item_latency",
  "delays": {
    "server_save_ms": 40
  },
  "add_before": {
    "user_visible_ms": {
      "count": 12,
      "avg_ms": 48.22175,
      "p50_ms": 48.7,
      "p95_ms": 49.333,
      "min_ms": 46.737,
      "max_ms": 49.805
    },
    "local_write_ms": {
      "count": 12,
      "avg_ms": 2.08675,
      "p50_ms": 2.335,
      "p95_ms": 2.406,
      "min_ms": 1.41,
      "max_ms": 2.81
    },
    "server_sync_ms": {
      "count": 12,
      "avg_ms": 45.7935,
      "p50_ms": 45.74,
      "p95_ms": 46.49,
      "min_ms": 44.82,
      "max_ms": 47.464
    },
    "reload_ms": {
      "count": 12,
      "avg_ms": 0.33425,
      "p50_ms": 0.328,
      "p95_ms": 0.488,
      "min_ms": 0.193,
      "max_ms": 0.5
    },
    "background_ms": {
      "count": 12,
      "avg_ms": 0.0,
      "p50_ms": 0.0,
      "p95_ms": 0.0,
      "min_ms": 0.0,
      "max_ms": 0.0
    },
    "total_ms": {
      "count": 12,
      "avg_ms": 48.22175,
      "p50_ms": 48.7,
      "p95_ms": 49.333,
      "min_ms": 46.737,
      "max_ms": 49.805
    }
  },
  "add_after": {
    "user_visible_ms": {
      "count": 12,
      "avg_ms": 3.0978333333333334,
      "p50_ms": 3.294,
      "p95_ms": 3.769,
      "min_ms": 1.874,
      "max_ms": 4.103
    },
    "local_write_ms": {
      "count": 12,
      "avg_ms": 3.0978333333333334,
      "p50_ms": 3.294,
      "p95_ms": 3.769,
      "min_ms": 1.874,
      "max_ms": 4.103
    },
    "server_sync_ms": {
      "count": 12,
      "avg_ms": 0.0,
      "p50_ms": 0.0,
      "p95_ms": 0.0,
      "min_ms": 0.0,
      "max_ms": 0.0
    },
    "reload_ms": {
      "count": 12,
      "avg_ms": 0.0,
      "p50_ms": 0.0,
      "p95_ms": 0.0,
      "min_ms": 0.0,
      "max_ms": 0.0
    },
    "background_ms": {
      "count": 12,
      "avg_ms": 45.800333333333334,
      "p50_ms": 45.145,
      "p95_ms": 50.571,
      "min_ms": 44.011,
      "max_ms": 50.607
    },
    "total_ms": {
      "count": 12,
      "avg_ms": 48.89816666666666,
      "p50_ms": 48.455,
      "p95_ms": 53.959,
      "min_ms": 45.926,
      "max_ms": 54.674
    }
  },
  "edit_before": {
    "user_visible_ms": {
      "count": 12,
      "avg_ms": 46.72075,
      "p50_ms": 46.736,
      "p95_ms": 47.831,
      "min_ms": 45.624,
      "max_ms": 47.852
    },
    "local_write_ms": {
      "count": 12,
      "avg_ms": 0.899,
      "p50_ms": 0.923,
      "p95_ms": 1.082,
      "min_ms": 0.558,
      "max_ms": 1.324
    },
    "server_sync_ms": {
      "count": 12,
      "avg_ms": 45.51375,
      "p50_ms": 45.467,
      "p95_ms": 46.092,
      "min_ms": 44.638,
      "max_ms": 46.509
    },
    "reload_ms": {
      "count": 12,
      "avg_ms": 0.3016666666666667,
      "p50_ms": 0.296,
      "p95_ms": 0.403,
      "min_ms": 0.19,
      "max_ms": 0.429
    },
    "background_ms": {
      "count": 12,
      "avg_ms": 0.0,
      "p50_ms": 0.0,
      "p95_ms": 0.0,
      "min_ms": 0.0,
      "max_ms": 0.0
    },
    "total_ms": {
      "count": 12,
      "avg_ms": 46.72075,
      "p50_ms": 46.736,
      "p95_ms": 47.831,
      "min_ms": 45.624,
      "max_ms": 47.852
    }
  },
  "edit_after": {
    "user_visible_ms": {
      "count": 12,
      "avg_ms": 1.5745833333333332,
      "p50_ms": 1.652,
      "p95_ms": 1.886,
      "min_ms": 0.966,
      "max_ms": 2.054
    },
    "local_write_ms": {
      "count": 12,
      "avg_ms": 1.5745833333333332,
      "p50_ms": 1.652,
      "p95_ms": 1.886,
      "min_ms": 0.966,
      "max_ms": 2.054
    },
    "server_sync_ms": {
      "count": 12,
      "avg_ms": 0.0,
      "p50_ms": 0.0,
      "p95_ms": 0.0,
      "min_ms": 0.0,
      "max_ms": 0.0
    },
    "reload_ms": {
      "count": 12,
      "avg_ms": 0.0,
      "p50_ms": 0.0,
      "p95_ms": 0.0,
      "min_ms": 0.0,
      "max_ms": 0.0
    },
    "background_ms": {
      "count": 12,
      "avg_ms": 47.54575,
      "p50_ms": 49.295,
      "p95_ms": 50.508,
      "min_ms": 44.088,
      "max_ms": 50.561
    },
    "total_ms": {
      "count": 12,
      "avg_ms": 49.120333333333335,
      "p50_ms": 50.842,
      "p95_ms": 51.632,
      "min_ms": 45.442,
      "max_ms": 51.822
    }
  },
  "improvement_ms": {
    "add_user_visible_avg_ms": 45.123916666666666,
    "edit_user_visible_avg_ms": 45.146166666666666
  }
}
```

## Interpretation

- The dominant latency was exactly what the plan predicted: synchronous server sync on the user-visible path.
- The update does not materially reduce full completion time; it moves that cost into background work, which is the right UX tradeoff for this workflow.
- Server bulk-updating `has_charge_items` removes one avoidable per-event loop, but the main benchmark gain comes from returning immediately after local write.

## Limitations

- This is a controlled benchmark, not a live-network measurement.
- The synthetic fixture isolates the create/edit charge-item path and intentionally avoids first-time record-resolution latency.
- Real-device UX should still be spot-checked against a local or staging server.
