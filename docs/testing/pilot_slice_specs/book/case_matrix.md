# Book Pilot Case Matrix

| Case ID | Test Purpose | Real App Scenario | Workflow Position | Expected Result | Mapped Test |
|---|---|---|---|---|---|
| BOOK-UNIT-001 | verify default listing hides archived books | user opens Book List | WF-BOOK-03 | active list excludes archived entries | `test/app/unit/repositories/book/book_repository_impl_read_test.dart` |
| BOOK-UNIT-002 | verify archive operation updates visibility | user archives old book | WF-BOOK-04 | book is archived, hidden from active list | `test/app/unit/repositories/book/book_repository_impl_write_test.dart` |
| BOOK-UNIT-003 | verify create requires registration credentials | user creates book before setup | WF-BOOK-02 | create fails with clear exception | `test/app/unit/repositories/book/book_repository_impl_create_test.dart` |
| BOOK-UNIT-004 | verify create uses server UUID then stores locally | user creates book after setup | WF-BOOK-01 | created book UUID equals server UUID and exists locally | `test/app/unit/repositories/book/book_repository_impl_create_test.dart` |
| BOOK-UNIT-005 | verify saved order application and new-book precedence | user reorders books and later adds new one | WF-BOOK-05 | saved order applied; unsaved books appear first | `test/app/unit/services/book/book_order_service_test.dart` |
| BOOK-UNIT-006 | verify update trims and persists name; empty name is rejected | user renames a book | WF-BOOK-06 | valid rename saved; empty rename fails fast | `test/app/unit/repositories/book/book_repository_impl_update_test.dart` |
| BOOK-UNIT-007 | verify update fails for missing book | user renames a deleted/missing book | WF-BOOK-06 | explicit "Book not found" failure | `test/app/unit/repositories/book/book_repository_impl_update_test.dart` |
| BOOK-UNIT-008 | verify list-server-books requires registration credentials | user opens import dialog before setup | WF-BOOK-07 | request is blocked before API call | `test/app/unit/repositories/book/book_repository_impl_server_test.dart` |
| BOOK-UNIT-009 | verify list-server-books forwards search query and auth credentials | user searches server books by keyword | WF-BOOK-07 | API called with search + credentials; result returned | `test/app/unit/repositories/book/book_repository_impl_server_test.dart` |
| BOOK-UNIT-010 | verify server-info 404 path returns null | user checks metadata of non-existing server book | WF-BOOK-08 | null returned for safe UI handling | `test/app/unit/repositories/book/book_repository_impl_server_test.dart` |
| BOOK-UNIT-011 | verify pull rejects duplicate-local book | user tries importing an already-local book | WF-BOOK-07 | pull blocked with duplicate-local error | `test/app/unit/repositories/book/book_repository_impl_server_test.dart` |
| BOOK-UNIT-012 | verify pull persists server book on valid payload | user imports valid server book | WF-BOOK-07 | local book row created with server data | `test/app/unit/repositories/book/book_repository_impl_server_test.dart` |
