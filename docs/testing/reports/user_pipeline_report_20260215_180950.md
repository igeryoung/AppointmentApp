# User Pipeline Automation Report

Date: 2026-02-15 18:09:53 CST
Mode: `server`
Overall Status: **PASS**
Report Path: `docs/testing/reports/user_pipeline_report_20260215_180950.md`
Checklist Source: `docs/testing/physical_device_test_checklist.md`

## Execution Summary

- Total steps: 2
- Passed: 2
- Failed: 0
- Skipped: 0
- Server env file: `.env.integration`

## Ordered Pipeline Results

| Step | Status | Duration | Command |
|---|---|---:|---|
| Pipeline 11 - Live Fixture Provision (create book -> create event) | PASS | 1s | `dart run tool/create_event_metadata_fixture.dart` |
| Pipeline 12 - Live Event Metadata Roundtrip | PASS | 2s | `flutter test test/app/integration/event_metadata_server_smoke_test.dart --reporter compact` |

## Checklist Coverage Mapping (Automate Everything Possible)

| Checklist Section | Automation Status | Coverage Notes |
|---|---|---|
| 1. App Launch & Setup | Partial | Automated: device credential persistence + app bootstrap widget (`test/widget_test.dart`, device repository tests). Manual-only: physical install/uninstall and real setup UI navigation. |
| 2. Book Behavior | High (Partial) | Automated: create/blank-name validation, rename trim, archive visibility, delete, reorder persistence logic, server import + duplicate guard. Manual-only: physical drag/drop gesture feel. |
| 3. Event Behavior | High (Partial) | Automated: create/edit/remove/reschedule/delete/query/sync-upsert via event repository + controller flow tests. Manual-only: full schedule screen rendering across day/week on physical device. |
| 4. Note Behavior | Partial | Automated: record-shared note semantics, save/update/delete/batch/sync apply + event-detail save flow. Manual-only: handwriting UX validation on real touch device. |
| 5. Drawing Behavior | Partial | Automated: save/update/load/clear/range preload/batch semantics in drawing repository tests. Manual-only: canvas interaction smoothness and visual fidelity on device. |
| 6. Device Credentials & Session | Partial | Automated: save/get/replace credential behavior. Manual-only: repeated relaunch behavior on actual installed app binary. |
| 7. Offline / Online Connectivity | Partial | Automated: server sync failure path and live metadata roundtrip (`event_metadata_server_smoke_test.dart`) when server env configured. Manual-only: airplane-mode OS-level toggling and UX messaging. |
| 8. Performance Sanity (Manual) | Manual-only | Not automatable in current unit/integration test stack; requires physical profiling and user-perceived latency checks. |

## Manual-Only Items (Explicit)

- Fresh install/uninstall and physical setup journey.
- Real touch interactions for schedule/note/drawing gestures.
- Airplane mode toggling and reconnect behavior on actual device network stack.
- Performance/fps/input latency validation on target hardware.
