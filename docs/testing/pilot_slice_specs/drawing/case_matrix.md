# Drawing Pilot Case Matrix

| Case ID | Test Purpose | Real App Scenario | Workflow Position | Expected Result | Mapped Test |
|---|---|---|---|---|---|
| DRAWING-UNIT-001 | verify normalized-day cache read/write | user loads drawing on same day with different time context | WF-DRAWING-01 | drawing resolves by date boundary normalization | `test/app/unit/repositories/drawing/drawing_repository_impl_test.dart` |
| DRAWING-UNIT-002 | verify update-in-place semantics | user saves drawing multiple times for same day/view | WF-DRAWING-02 | single row remains and stroke payload updates | `test/app/unit/repositories/drawing/drawing_repository_impl_test.dart` |
| DRAWING-UNIT-003 | verify cache delete behavior | user clears day drawing cache | WF-DRAWING-03 | matching cache entry removed | `test/app/unit/repositories/drawing/drawing_repository_impl_test.dart` |
| DRAWING-UNIT-004 | verify range preload filtering | app fetches drawings by date range/view mode | WF-DRAWING-04 | results filtered by range and optional view mode | `test/app/unit/repositories/drawing/drawing_repository_impl_test.dart` |
| DRAWING-UNIT-005 | verify batch save insert/update behavior | app persists drawing batch | WF-DRAWING-05 | batch save supports initial insert and later update | `test/app/unit/repositories/drawing/drawing_repository_impl_test.dart` |
