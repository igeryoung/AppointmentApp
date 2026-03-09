# Pre-Real-Case Risk Survey

Date: 2026-03-09 (CST)  
Scope: App + server readiness before physical real-case testing

## Current Readiness Snapshot

- Latest full pipeline run (`2026-03-09 20:21 CST`): 12/13 PASS, 1 FAIL.
- Blocking failure is Pipeline 10 (setup widget path test).
- Live roundtrip (Pipeline 12) passed in latest full run, but historical stability is mixed.
- Static analysis: 312 issues (quality/safety debt, not compile blockers).

## Potential Failure Matrix

| ID | Potential Failure | Likelihood | Impact | Evidence | Detection During Real Test | Recommended Mitigation |
|---|---|---|---|---|---|---|
| R1 | Setup error handling regression (wrong/changed error text, setup flow not showing expected failure message) | High | Medium | `test/app/widget/app_bootstrap_setup_test.dart:58` expects English text; setup screen throws localized text from `lib/screens/server_setup_screen.dart:228`. Latest runs failed Pipeline 10 on 2026-03-09. | Fresh install, enter unreachable URL, confirm error appears and setup does not proceed. | Make test assert localization key output (or localized matcher), not hardcoded English text. |
| R2 | Widget tests using real `HttpClient` in test binding can produce false negatives | High | Low-Medium | Pipeline 10 failure log warns HTTP is forced to 400 in widget tests; see `docs/testing/reports/user_pipeline_report_20260309_201742.md`. | Re-run pipeline multiple times and compare failure pattern. | Mock network in widget tests (`HttpOverrides`/fake client) to remove environment coupling. |
| R3 | Unauthorized record API access (possible integrity/security issue) | Medium | High | `server/lib/routes/record_routes.dart` has no `x-device-id/x-device-token` checks, unlike note routes (`server/lib/routes/note_routes.dart:831-874`). | Call `/api/records/*` without credentials and verify response policy. | Add auth + access checks to all record routes before external rollout. |
| R4 | Live integration roundtrip instability (pipeline sometimes FAIL/SKIP) | Medium | Medium-High | Historical Pipeline 12 status across report files: PASS=10, FAIL=4, SKIP=9. Latest run passed in 175s (`user_pipeline_report_20260309_201742.md`). | Run full pipeline at least 3 consecutive times before release. | Add retry/health gate around fixture provision + live smoke; block release when FAIL/SKIP occurs. |
| R5 | Autosave conflict policy can overwrite local unsynced note edits with server version | Medium | High (user trust/data perception) | `lib/screens/event_detail/event_detail_controller.dart:647-666` uses server-authoritative autosave path (`autosave skipped: server note wins`). | Two-device concurrent edit test on same record note with autosave enabled. | Add explicit user-visible conflict notice and local draft recovery option. |
| R6 | Async UI context lifecycle risks (actions after async gap) | Medium | Medium | Analyzer reports 14 `use_build_context_synchronously` warnings (`flutter analyze`, 2026-03-09). | Rapid navigation/back during long operations (setup/save/sync). | Guard with `if (!mounted) return;` consistently after await before UI calls. |
| R7 | Silent failure paths due empty catches | Medium | Medium | Analyzer reports empty catches in critical controllers/services (example in event detail and DB lock mixins). | Force network/DB error and verify UI surfaces error + recovery path. | Replace empty catches with logged + typed failure handling. |
| R8 | Offline/online reconnect merge behavior not fully automated | Medium | Medium-High | Checklist marks reconnect merge/manual network behavior as partially or non-automated (`docs/testing/physical_device_test_checklist.md`). | Airplane mode edit attempts, reconnect, verify no duplicate objects and clean merge. | Add one dedicated integration case for reconnect merge + duplicate guard. |
| R9 | Real-device performance regressions (dense schedule, handwriting-heavy screens) | Medium | Medium-High | Checklist section 8 is manual-only. | Measure cold start, scroll smoothness, note/drawing latency on target device. | Define performance pass thresholds and fail release if exceeded. |
| R10 | Pipeline signal noise (some historical runs failed all steps at 0-1s) can hide real status | Medium | Medium | Full reports on 2026-02-28 and 2026-03-08 show near-total 0s failures. | Trigger pipeline from clean environment and compare with baseline run. | Add startup lock/preflight check and fail-fast reason output in pipeline script. |

## Quality Debt Signals (from `flutter analyze`, 2026-03-09)

- Total issues: 312
- Top categories:
  - `avoid_print` (96)
  - `deprecated_member_use` (38)
  - `deprecated_member_use_from_same_package` (18)
  - `unnecessary_cast` (17)
  - `use_build_context_synchronously` (14)
  - `unused_import` (14)

## Release Gate Recommendation

- **Do not start broad real-case testing yet** until:
  1. Pipeline 10 regression is fixed and green.
  2. Record route auth policy is confirmed/fixed.
  3. One full manual offline/online reconnect pass and one performance sanity pass are completed on target device.
