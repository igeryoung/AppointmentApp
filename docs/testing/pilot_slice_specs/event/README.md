# Event Pilot Slice Spec

Purpose:
- define real event workflows in app.
- map each workflow to focused unit tests.
- keep the slice modular and extendable.

Scope (this pilot):
- app-side event repository behavior.
- read, write, and sync-safe local behaviors.
- no server route tests in this pilot iteration.

How to run:
- `flutter test test/app/unit/repositories/event --reporter compact`

Structure:
- `app_workflow_scenarios.md`: real user workflows.
- `case_matrix.md`: test purpose + scenario + expected result + mapped test.

Implemented test slice layout:
- `test/app/unit/repositories/event/event_repository_impl_read_test.dart`
- `test/app/unit/repositories/event/event_repository_impl_write_test.dart`
- `test/app/unit/repositories/event/event_repository_impl_sync_test.dart`
- `test/app/support/fixtures/event_fixtures.dart`
- `test/app/support/db_seed.dart`
- `test/app/support/test_db_path.dart`

Grouped bullet plan (event pilot):
- repository-read: list by book with stable ordering; date-range boundaries; name/record lookup paths over record-based schema.
- repository-write: create/update/delete behavior; soft-remove with reason validation; change-time linkage between old and new events.
- repository-sync: apply server change as insert/update upsert; fetch by server ID.

Legacy/debt flags in this slice:
- event data shape is still mixed in some server integration code paths; repository now enforces record-based schema locally.
