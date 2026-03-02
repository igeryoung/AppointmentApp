# Event Pipeline Stage Latency

Date: March 2, 2026

Source:

- `test/app/benchmarks/event_pipeline_stage_latency_live_test.dart`

Method:

- Live benchmark against the updated local server at `https://localhost:8080`.
- Temporary book/event/note fixture provisioned via `tool/create_event_metadata_fixture.dart`.
- Samples: 6 measured iterations after 2 warmup iterations.
- Local stages use real `PRDDatabaseService` SQLite reads/writes.
- Fetch pipeline matches current existing-event detail load:
  - local credentials
  - `fetchEventDetailBundle`
  - local cache write
- Update pipeline matches current existing-event save path:
  - local credentials
  - `updateEventDetailBundle`
  - local cache write
- A second update variant includes note save to show the extra cost when handwriting changed.

## Fetch Pipeline

| Stage | Avg ms | P50 ms | P95 ms |
|---|---:|---:|---:|
| `credentials_local` | 1.72 | 1.78 | 2.05 |
| `fetch_bundle` | 780.16 | 786.02 | 874.56 |
| `cache_local_metadata` | 4.38 | 4.69 | 5.33 |
| `total` | 786.42 | 790.76 | 880.53 |

## Update Pipeline

Metadata only:

| Stage | Avg ms | P50 ms | P95 ms |
|---|---:|---:|---:|
| `credentials_local` | 0.80 | 0.63 | 1.64 |
| `update_bundle` | 1349.33 | 1281.68 | 1693.23 |
| `cache_local_metadata` | 4.40 | 4.80 | 6.62 |
| `total` | 1354.78 | 1287.23 | 1700.79 |

Metadata plus note save:

| Stage | Avg ms | P50 ms | P95 ms |
|---|---:|---:|---:|
| `credentials_local` | 0.69 | 0.67 | 1.53 |
| `update_bundle` | 1280.80 | 1258.60 | 1455.89 |
| `cache_local_metadata` | 4.50 | 5.35 | 5.97 |
| `save_note` | 1048.19 | 1028.44 | 1323.49 |
| `total` | 2334.43 | 2276.17 | 2588.95 |

## Conclusion

- The main latency is server round-trips and server-side processing, not local SQLite.
- Local credential reads and local cache writes are effectively negligible: about `1-5 ms`.
- Existing-event fetch now spends almost all of its time in one bundled server call.
- Existing-event metadata update now spends almost all of its time in one bundled server call.
- If handwriting changed, note save still adds another roughly `1.0 s` stage.
- Compared with the pre-refactor measurements, endpoint consolidation removes the largest client-side fetch/update overhead by collapsing serialized metadata calls into one request.

## Deployment Note

- These numbers are from the updated local server code. The remote Railway deployment must be updated with the new `event-details` endpoints before production will show the same stage profile.
