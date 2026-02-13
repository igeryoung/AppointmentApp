# Note Pilot Case Matrix

| Case ID | Test Purpose | Real App Scenario | Workflow Position | Expected Result | Mapped Test |
|---|---|---|---|---|---|
| NOTE-UNIT-001 | verify event-context note load via record_uuid | user opens note for events sharing same record | WF-NOTE-01 | both events resolve the same note; missing event returns null | `test/app/unit/repositories/note/note_repository_impl_test.dart` |
| NOTE-UNIT-002 | verify cache save insert/update behavior | user saves note repeatedly | WF-NOTE-02 | first save inserts and increments version; later save updates data and version | `test/app/unit/repositories/note/note_repository_impl_test.dart` |
| NOTE-UNIT-003 | verify cache delete behavior | user clears note cache from event context | WF-NOTE-03 | target record note removed without affecting other records | `test/app/unit/repositories/note/note_repository_impl_test.dart` |
| NOTE-UNIT-004 | verify per-book note listing distinctness | app loads all notes in current book | WF-NOTE-04 | one row per record note in book result | `test/app/unit/repositories/note/note_repository_impl_test.dart` |
| NOTE-UNIT-005 | verify batch save/get behavior | app batch preloads and stores notes | WF-NOTE-05 | saved notes retrievable by record UUID; missing keys ignored | `test/app/unit/repositories/note/note_repository_impl_test.dart` |
| NOTE-UNIT-006 | verify sync apply upsert behavior | app applies pulled note payloads | WF-NOTE-06 | missing note inserted; existing note updated | `test/app/unit/repositories/note/note_repository_impl_test.dart` |
