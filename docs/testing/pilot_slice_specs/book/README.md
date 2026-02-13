# Book Pilot Slice Spec

Purpose:
- define real book workflows in app.
- map each workflow to focused unit tests.
- keep this slice small, readable, and extensible.

Scope (this pilot):
- app-side book repository behavior.
- app-side book ordering behavior.
- no server route tests in this pilot iteration.

How to run:
- `flutter test test/app/unit/repositories/book --reporter compact`
- `flutter test test/app/unit/services/book --reporter compact`

Structure:
- `app_workflow_scenarios.md`: real user workflows.
- `case_matrix.md`: test purpose + scenario + expected result + mapped test.

Implemented test slice layout:
- `test/app/unit/repositories/book/book_repository_impl_create_test.dart`
- `test/app/unit/repositories/book/book_repository_impl_read_test.dart`
- `test/app/unit/repositories/book/book_repository_impl_server_test.dart`
- `test/app/unit/repositories/book/book_repository_impl_update_test.dart`
- `test/app/unit/repositories/book/book_repository_impl_write_test.dart`
- `test/app/unit/services/book/book_order_service_test.dart`
- `test/app/support/fixtures/book_fixtures.dart`
- `test/app/support/test_db_path.dart`

Grouped bullet plan (book pilot):
- repository-read: default list excludes archived books; lookup returns existing and null for missing UUID.
- repository-write: archive marks row and hides it from active list; delete removes target row.
- repository-create: reject empty name; reject missing device credentials; create local row from server UUID on success.
- repository-update: trim and persist valid rename; reject empty rename; fail when target book is missing.
- repository-server: enforce credential gate for server list/info/pull; forward search query and auth; return null on server 404 info; block duplicate-local pull; persist valid pulled book payload.
- order-service: preserve original order when no saved order exists; put new/unsaved books first, then saved sequence; persist current order and load it back.

Legacy/debt flags in this slice:
- `BookRepositoryImpl.reorder()` is a placeholder and does not persist order in DB.
- Book creation currently requires server credentials and does not support local-offline create fallback.
