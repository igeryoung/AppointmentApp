# Stage 1 Testing Report (Code-Truth Based)

Date: 2026-02-13  
Target: Production behavior (spec baseline)  
Method: Source-code inventory from `lib/` and `server/lib/` + current test execution status

## 1) Scope and Ground Rules

- Source of truth: current codebase only.
- Existing tests/docs are treated as secondary and may be stale.
- This report is a stage-1 unit-test spec baseline:
- list what to test (APIs/modules/behaviors),
- grouped bullet test plan,
- module-level coverage status,
- legacy/to-remove candidates flagged (no migration plan yet).

## 2) Current Coverage Snapshot (Module-Level)

## 2.1 Automated test execution reality

- Command run: `flutter test` and per-file `flutter test <file>`
- Result: only 2 test files pass; most test files fail at compile-time due to outdated imports/models.

Passing test files:
- `test/charge_items_section_test.dart`
- `test/models/cache_policy_test.dart`

Failing test files:
- `test/characterization/cache_behavior_test.dart`
- `test/characterization/database_operations_test.dart`
- `test/cubits/book_list_cubit_test.dart`
- `test/repositories/book_repository_test.dart`
- `test/screens/schedule_screen_behavior_test.dart`
- `test/screens/schedule_screen_preload_test.dart`
- `test/services/cache_manager_test.dart`
- `test/services/cache_policy_db_test.dart`
- `test/services/content_service_test.dart`
- `test/services/prd_database_service_test.dart`

## 2.2 Module-level coverage status

Frontend modules:
- App init/server setup: no runnable automated coverage.
- Book list flow: legacy tests exist but not runnable; effective coverage none.
- Schedule flow (date/event/drawing): legacy tests exist but not runnable; effective coverage none.
- Event detail flow (record/notes/charge items): partial runnable coverage only for charge-items widget; controller/sync paths uncovered.
- Database/repository layer: legacy tests exist but not runnable; effective coverage none.
- Sync/network layer: no runnable automated coverage.
- Handwriting widget/core interaction: no runnable automated coverage.

Backend/API modules (`server/lib`):
- Device/Record/Book/Event/Note/Drawing/Sync/Batch/Dashboard routes: no server automated tests found; effective coverage none.

## 3) API Inventory To Test (Grouped, Internal APIs)

## 3.1 Device and auth bootstrap

Endpoints:
- `POST /api/devices/register`
- `GET /api/devices/<deviceId>`
- `POST /api/devices/sync-time`

Test bullets:
- register success and invalid password.
- missing fields and malformed payload handling.
- token validation behavior for `sync-time`.
- inactive device rejection.

## 3.2 Record domain

Endpoints:
- `POST /api/records/`
- `GET /api/records/<recordUuid>`
- `GET /api/records/by-number/<recordNumber>`
- `PUT /api/records/<recordUuid>`
- `DELETE /api/records/<recordUuid>`
- `POST /api/records/get-or-create`
- `POST /api/records/validate`

Test bullets:
- uniqueness behavior for `(name, record_number)` (non-empty).
- empty `record_number` validation path.
- update with no fields returns bad request.
- soft-delete behavior and retrieval after delete.

## 3.3 Book creation and pull (server-store)

Endpoints:
- `POST /api/create-books`
- `GET /api/books/list`
- `POST /api/books/pull/<bookUuid>`
- `GET /api/books/<bookUuid>/info`

Test bullets:
- auth required on all endpoints.
- pull/info on unknown book returns not-found path.
- list search query behavior.
- cross-device pull access tracking (`book_device_access`) behavior.

## 3.4 Event query APIs

Endpoints:
- `GET /api/books/<bookUuid>/events`
- `GET /api/books/<bookUuid>/events/<eventId>`
- `GET /api/books/<bookUuid>/records/<recordUuid>`

Test bullets:
- date-range filter boundaries (`startDate`, `endDate`).
- credential and book ownership checks.
- event/record not-found responses.
- `has_note`, `is_removed`, `new_event_id` serialization integrity.

## 3.5 Notes APIs (record/event dual paths)

Endpoints:
- `POST /api/notes/batch`
- `GET/POST/DELETE /api/books/<bookUuid>/records/<recordUuid>/note`
- `GET/POST/DELETE /api/books/<bookUuid>/events/<eventId>/note`

Test bullets:
- auth and book ownership checks.
- event-based path record resolution behavior.
- auto-create event from `eventData` in event-based POST.
- optimistic-locking conflict response (`409`, serverVersion/serverNote).
- delete behavior updates `has_note` state.
- batch payload validation and response count behavior.

## 3.6 Drawings APIs

Endpoints:
- `POST /api/drawings/batch`
- `GET/POST/DELETE /api/books/<bookId>/drawings`

Test bullets:
- required query/body fields (`date`, `viewMode`, `strokesData`).
- auth/book ownership checks.
- optimistic-locking conflict response (`409`, serverVersion/serverDrawing).
- soft-delete behavior and not-found path.
- date-range batch result filtering.

## 3.7 Sync APIs

Endpoints:
- `POST /api/sync/pull`
- `POST /api/sync/push`
- `POST /api/sync/full`
- `POST /api/sync/resolve-conflict`

Test bullets:
- invalid credentials path.
- empty local changes push behavior.
- conflict generation and conflict payload shape.
- full sync ordering (apply local then fetch server changes).
- conflict resolution `merge` update path.

## 3.8 Batch API

Endpoint:
- `POST /api/batch/save`

Test bullets:
- auth and payload size (`<=1000`) validation.
- all-or-nothing transaction behavior.
- mixed note+drawing conflict rollback behavior.
- status code mapping (400/403/409/413/500).

## 3.9 Dashboard APIs

Endpoints:
- `POST /api/dashboard/auth/login`
- `GET /api/dashboard/stats`
- `GET /api/dashboard/devices`
- `GET /api/dashboard/books`
- `GET /api/dashboard/records`
- `GET /api/dashboard/records/<recordUuid>`
- `GET /api/dashboard/events`
- `GET /api/dashboard/events/<eventId>`
- `GET /api/dashboard/events/<eventId>/note`
- `GET /api/dashboard/notes`
- `GET /api/dashboard/drawings`
- `GET /api/dashboard/backups`
- `GET /api/dashboard/sync-logs`

Test bullets:
- login success/failure and token header requirement.
- list vs stats branch behavior on `/events`.
- serialization format (camelCase, timestamps) consistency.

## 4) Frontend Behavior Inventory To Test (Grouped)

## 4.1 App startup and server setup

Modules:
- `lib/app.dart`
- `lib/screens/server_setup_screen.dart`

Test bullets:
- first-launch path goes to server setup if no `device_info`.
- server URL health-check gate.
- device registration success/failure flow.
- service registration and navigation to book list.

## 4.2 Book list flow

Modules:
- `lib/screens/book_list/book_list_screen.dart`
- `lib/screens/book_list/book_list_controller.dart`

Test bullets:
- initial load/render states.
- create/rename/archive/delete flows.
- reorder persistence behavior.
- restore-from-server and server-settings update flow.

## 4.3 Schedule flow

Modules:
- `lib/screens/schedule_screen.dart`
- `lib/screens/schedule/schedule_controller.dart`
- `lib/cubits/schedule_cubit.dart`
- `lib/screens/schedule/services/*`
- `lib/utils/schedule/schedule_layout_utils.dart`

Test bullets:
- date window logic (2-day/3-day anchored windows).
- navigation actions (page, +/-90, +/-180, today).
- event load fallback (server then local).
- create/edit/remove/delete/change-time/drop behavior.
- drawing mode toggle, auto-save on navigation/back/lifecycle.
- drawing load/save race handling and per-window canvas behavior.
- offline status updates and sync notification behavior.

## 4.4 Event detail flow

Modules:
- `lib/screens/event_detail/event_detail_screen.dart`
- `lib/screens/event_detail/event_detail_controller.dart`

Test bullets:
- initial server refresh and note load behavior.
- record number validation on blur.
- name/record number autocomplete interactions.
- save event (new/update) + note save flow.
- remove/delete/change-time actions.
- charge item add/edit/delete/toggle paid/filter behavior.
- offline/online state handling for note sync.

## 4.5 Repository/database core behavior

Modules:
- `lib/services/database/prd_database_service.dart` + mixins
- `lib/repositories/*_impl.dart`

Test bullets:
- record-based identity behavior (`record_uuid`, note sharing).
- create/update/delete and soft-delete semantics.
- event time change (new event + old event linkage).
- note save/update/delete and version behavior.
- drawing unique key (`book_uuid`,`date`,`view_mode`) behavior.
- device credential persistence and server URL persistence.

## 4.6 Handwriting behavior

Modules:
- `lib/widgets/handwriting_canvas.dart`
- `lib/screens/event_detail/widgets/handwriting_*`
- `lib/screens/schedule/services/schedule_drawing_service.dart`

Test bullets:
- stroke capture/render/serialization.
- page switching and callback propagation.
- erase tracking (`erasedStrokesByEvent`) behavior.
- canvas update behavior when incoming note changes.

## 5) Manual Behavior Verification Matrix (Production-Oriented)

Note: this is a manual check plan template, not execution results.

| Group | Scenario | Expected |
|---|---|---|
| Startup | First launch with empty local DB | redirected to server setup screen |
| Startup | Valid URL + correct registration password | registration succeeds, enters book list |
| Startup | Invalid registration password | error shown, remains on registration step |
| Book List | Create book | new book appears immediately and persists after refresh |
| Book List | Rename/archive/delete book | UI and data reflect operation after refresh |
| Book List | Restore from server | selected server book appears locally with events/notes/drawings |
| Schedule | Change date window | events and drawing reflect new window only |
| Schedule | Drag/drop event within valid hours | event time changed and persisted |
| Schedule | Remove event with reason | event marked removed with reason, still queryable as removed |
| Schedule | Delete event permanently | event no longer in active list and local deletion persists |
| Schedule | Toggle drawing mode and draw | strokes persist when leaving screen and re-opening |
| Event Detail | Enter record number with conflict name | validation fails and blocks save |
| Event Detail | Save new event with note | event + note visible after reopen |
| Event Detail | Change event time from detail | old/new linkage reflected in schedule |
| Event Detail | Charge items CRUD | totals and item states update correctly |
| API | Note save conflict (stale version) | API returns 409 with serverVersion/serverNote |
| API | Drawing save conflict (stale version) | API returns 409 with serverVersion/serverDrawing |
| API | Sync full with valid credentials | pull/push operation succeeds, sync time updated |

## 6) Legacy / To-Remove Candidates (Flag Only)

High-confidence legacy/inconsistent areas identified from current code:

- Legacy test import paths:
- many tests import removed path `lib/services/prd_database_service.dart` (current path is under `lib/services/database/`).
- Legacy ID model assumptions in tests:
- tests still expect integer `book.id` / `eventId` signatures; current domain uses UUID-centric `book.uuid` and record-based note linkage.
- Removed service still referenced by tests:
- `lib/services/cache_manager.dart` is referenced by tests but file is absent.
- Deprecated service still active in runtime flows:
- `ContentService` is marked deprecated but still used by schedule/event-detail controllers.
- API client endpoints likely stale vs server routes:
- `GET /api/books/{bookUuid}/persons/{recordNumber}` exists in client but no matching server route found.
- charge-item endpoints used in client (`/api/records/{recordUuid}/charge-items`, `/api/charge-items/{id}`) have no matching route implementation in `server/lib/routes/`.
- Notes batch contract mismatch:
- client sends `eventIds`; server expects `record_uuids`.
- Batch service schema mismatch:
- `server/lib/services/batch_service.dart` still uses old columns (`books.id`, `events.book_id`, `notes.event_id`) while schema/routes are UUID + record-based.
- Sync coordinator behavior currently stubbed:
- `SyncCoordinator.syncNow()` returns "Full sync temporarily disabled" without running actual full sync.
- Deprecated UI behavior still referenced:
- schedule "old events toggle" path is deprecated no-op but related labels still exist.

## 7) Grouped Bullet Plan (Execution Backlog Seed)

Phase A (stabilize baseline):
- establish a green "smoke" test set for startup, book list, schedule load, event detail save.
- create API contract tests for notes/drawings/event query/auth.
- remove or quarantine legacy tests that target deleted paths.

Phase B (core behavior):
- cover record-based event/note linkage and time-change semantics.
- cover drawing conflict/retry and lifecycle auto-save paths.
- cover record validation and charge-item workflows.

Phase C (sync and admin):
- cover sync pull/push/full/conflict resolution paths.
- cover dashboard auth and main read endpoints.
- decide keep/remove for batch API based on schema alignment.
