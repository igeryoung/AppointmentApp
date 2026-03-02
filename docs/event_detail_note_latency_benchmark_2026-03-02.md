# Event Detail Note Latency Benchmark

Date: March 2, 2026

Scope: Measure note save latency before and after removing the unconditional server-note prefetch from `EventDetailController.saveNoteToServer()`.

Benchmark file:

- `test/app/benchmarks/event_detail_note_latency_benchmark_test.dart`

Method:

- Controlled benchmark with synthetic delays.
- Legacy path model: prefetch current server note, then save.
- New path model: save optimistically from local note state, fetch only on conflict/autosave-protection paths.
- Configured synthetic delays:
  - prefetch: 25 ms
  - save: 35 ms
- Samples per scenario: 12 after warmup.

## Results

| Scenario | Before avg | After avg | Improvement |
|---|---:|---:|---:|
| Create note | 66.54 ms | 38.73 ms | 27.81 ms |
| Update note | 65.52 ms | 38.54 ms | 26.98 ms |

Detailed output captured from the benchmark run:

```json
{
  "benchmark": "event_detail_note_save_latency",
  "delays": {
    "prefetch_ms": 25,
    "save_ms": 35
  },
  "create_note_before": {
    "count": 12,
    "avg_ms": 66.53883333333333,
    "p50_ms": 66.712,
    "p95_ms": 67.229,
    "min_ms": 65.278,
    "max_ms": 67.312
  },
  "create_note_after": {
    "count": 12,
    "avg_ms": 38.72725,
    "p50_ms": 38.827,
    "p95_ms": 38.979,
    "min_ms": 37.426,
    "max_ms": 39.17
  },
  "update_note_before": {
    "count": 12,
    "avg_ms": 65.52141666666667,
    "p50_ms": 66.2,
    "p95_ms": 66.993,
    "min_ms": 62.818,
    "max_ms": 67.557
  },
  "update_note_after": {
    "count": 12,
    "avg_ms": 38.53908333333334,
    "p50_ms": 38.816,
    "p95_ms": 39.015,
    "min_ms": 37.533,
    "max_ms": 40.046
  },
  "improvement_ms": {
    "create_avg_ms": 27.81158333333333,
    "update_avg_ms": 26.98233333333333
  }
}
```

## Interpretation

- The measured gain is almost exactly the eliminated prefetch round-trip plus a small amount of local processing overhead.
- Create and update benefit similarly because both previously paid the same prefetch cost in the no-conflict path.
- This benchmark does not measure live server behavior. It isolates the controller-path improvement under stable artificial latency so before/after comparison is clean.

## Remaining Work

- Measure the same path against a real local or staging server.
- Extend the benchmark to conflict and autosave scenarios.
- Continue the larger server-first refactor by removing local event/record content writes from the event detail save path.
