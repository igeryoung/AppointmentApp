# Note Pilot Slice Spec

Purpose:
- define real note workflows in app.
- map each workflow to focused unit tests.
- keep the slice concise and extensible.

Scope (this pilot):
- app-side note repository cache behavior.
- record-linked note access from events.
- no server route tests in this pilot iteration.

How to run:
- `flutter test test/app/unit/repositories/note --reporter compact`

Structure:
- `app_workflow_scenarios.md`: real user workflows.
- `case_matrix.md`: test purpose + scenario + expected result + mapped test.

Implemented test slice layout:
- `test/app/unit/repositories/note/note_repository_impl_test.dart`
- `test/app/support/fixtures/note_fixtures.dart`
- `test/app/support/fixtures/event_fixtures.dart`
- `test/app/support/db_seed.dart`
- `test/app/support/test_db_path.dart`

Grouped bullet plan (note pilot):
- record-linked caching: load note from event via record_uuid.
- cache writes: insert/update with version progression.
- cache delete: remove note by event context.
- list behaviors: distinct notes per book.
- batch operations: batch save + batch get consistency.
- sync apply: server upsert for note rows.

Legacy/debt flags in this slice:
- note locking and conflict-resolution behaviors are not covered in this pilot and should be added in a sync-focused slice.
