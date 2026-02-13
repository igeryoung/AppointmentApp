# Event Pilot Case Matrix

| Case ID | Test Purpose | Real App Scenario | Workflow Position | Expected Result | Mapped Test |
|---|---|---|---|---|---|
| EVENT-UNIT-001 | verify per-book event filtering and ordering | user views schedule events for one book | WF-EVENT-01 | only target-book events returned in ascending start order | `test/app/unit/repositories/event/event_repository_impl_read_test.dart` |
| EVENT-UNIT-002 | verify date range boundary semantics | user views events for selected date window | WF-EVENT-01 | start is inclusive, end is exclusive | `test/app/unit/repositories/event/event_repository_impl_read_test.dart` |
| EVENT-UNIT-003 | verify name/record lookup queries on record-based schema | user searches with name + record number | WF-EVENT-01 | distinct names/numbers/pairs and case-insensitive name lookup work | `test/app/unit/repositories/event/event_repository_impl_read_test.dart` |
| EVENT-UNIT-004 | verify create initializes persisted lifecycle fields | user creates event | WF-EVENT-02 | event saved with normalized timestamps and version=1 | `test/app/unit/repositories/event/event_repository_impl_write_test.dart` |
| EVENT-UNIT-005 | verify update persistence and validation | user edits event metadata | WF-EVENT-03 | version increments and null-ID update is rejected | `test/app/unit/repositories/event/event_repository_impl_write_test.dart` |
| EVENT-UNIT-006 | verify hard delete behavior | user deletes event | WF-EVENT-04 | target event removed; repeat delete returns not-found failure | `test/app/unit/repositories/event/event_repository_impl_write_test.dart` |
| EVENT-UNIT-007 | verify soft remove behavior | user removes event with reason | WF-EVENT-05 | event marked removed with trimmed reason; blank reason rejected | `test/app/unit/repositories/event/event_repository_impl_write_test.dart` |
| EVENT-UNIT-008 | verify time-change workflow linkage | user reschedules event | WF-EVENT-06 | new event created; original removed; old/new IDs linked | `test/app/unit/repositories/event/event_repository_impl_write_test.dart` |
| EVENT-UNIT-009 | verify sync apply upsert behavior | app applies pulled server event changes | WF-EVENT-07 | missing event inserted, existing event updated | `test/app/unit/repositories/event/event_repository_impl_sync_test.dart` |
| EVENT-UNIT-010 | verify server-ID lookup behavior | app resolves event by sync/server ID | WF-EVENT-07 | existing ID resolves event; missing ID returns null | `test/app/unit/repositories/event/event_repository_impl_sync_test.dart` |
