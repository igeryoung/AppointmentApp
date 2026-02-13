# Device Pilot Slice Spec

Purpose:
- define device-credential persistence workflows in app.
- map each workflow to focused unit tests.
- keep the slice compact and reusable.

Scope (this pilot):
- app-side device repository behavior.
- credential get/save/replace logic.
- no server route tests in this pilot iteration.

How to run:
- `flutter test test/app/unit/repositories/device --reporter compact`

Structure:
- `app_workflow_scenarios.md`: real user workflows.
- `case_matrix.md`: test purpose + scenario + expected result + mapped test.

Implemented test slice layout:
- `test/app/unit/repositories/device/device_repository_impl_test.dart`
- `test/app/support/test_db_path.dart`

Grouped bullet plan (device pilot):
- empty-state behavior: no credentials path.
- save/get behavior: persisted credentials are retrievable.
- replace behavior: conflict replace keeps single-row credential state.

Legacy/debt flags in this slice:
- server URL persistence is handled in database mixin paths and should be covered in a dedicated setup/sync slice.
