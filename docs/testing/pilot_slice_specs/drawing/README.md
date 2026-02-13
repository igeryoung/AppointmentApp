# Drawing Pilot Slice Spec

Purpose:
- define real schedule-drawing workflows in app.
- map each workflow to focused unit tests.
- keep the slice clear and extendable.

Scope (this pilot):
- app-side drawing repository cache behavior.
- single and batch cache operations.
- no server route tests in this pilot iteration.

How to run:
- `flutter test test/app/unit/repositories/drawing --reporter compact`

Structure:
- `app_workflow_scenarios.md`: real user workflows.
- `case_matrix.md`: test purpose + scenario + expected result + mapped test.

Implemented test slice layout:
- `test/app/unit/repositories/drawing/drawing_repository_impl_test.dart`
- `test/app/support/fixtures/drawing_fixtures.dart`
- `test/app/support/db_seed.dart`
- `test/app/support/test_db_path.dart`

Grouped bullet plan (drawing pilot):
- cache get/save: normalized-day lookup and write behavior.
- cache update/delete: update-in-place and explicit delete by day.
- batch queries: date-range + view-mode filtering.
- batch writes: insert/update behavior for list saves.

Legacy/debt flags in this slice:
- cache hit statistics and sync metadata paths are not covered in this pilot.
