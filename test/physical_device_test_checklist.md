# Physical Device Test Checklist

Use this checklist for real-device verification after unit tests pass.

`Trace` lists the primary automated pipeline/test IDs and the file to inspect for each behavior.

## Automation Reference

- Ordered automated pipeline runner:
  - `/Users/yangping/Studio/side-project/scheduleNote/tool/test_user_pipeline.sh`
- Automation guide:
  - `/Users/yangping/Studio/side-project/scheduleNote/docs/testing/user_pipeline_automation.md`
- Latest run reports:
  - `/Users/yangping/Studio/side-project/scheduleNote/docs/testing/reports/`
- Latest local automation snapshot:
  - `2026-03-12 23:03` local `--fast` run: Pipelines 01-09 PASS, Pipeline 10 FAIL, live Pipeline 12 not run in this workspace
  - Report: `/Users/yangping/Studio/side-project/scheduleNote/docs/testing/reports/user_pipeline_report_20260312_230320.md`
- Maintenance note:
  - Current automation scripts still reference the historical `docs/testing/physical_device_test_checklist.md` path

## Test Session Info

| Field | Value |
|---|---|
| Date | |
| Device Model / OS | |
| App Build (git commit / version) | |
| Server URL | |
| Tester | |

## 1. App Launch & Setup

| Done | Auto Test | Operation | Expected Behavior | Trace |
|---|---|---|---|---|
| [V] | [ ] | Install app fresh (clear old app data), then open app | App starts without crash and enters setup flow when no device credentials exist | Partial: P01 - DEVICE-UNIT-001 @ `test/app/unit/repositories/device/device_repository_impl_test.dart`; P10 - APP-WIDGET-001 @ `test/widget_test.dart` |
| [V] | [ ] | Enter invalid server URL / unreachable server and continue | App shows setup failure and does not proceed to book list | P10 - APP-WIDGET-002/003 @ `test/app/widget/app_bootstrap_setup_test.dart` |
| [V] | [V] | Register device with valid server config | Setup succeeds and app navigates to Book List | P12 - EVENT-INTEG-010 @ `test/app/integration/event_metadata/event_integ_010_device_session_contract_test.dart` |
| [V] | [ ] | Force close app and reopen | App keeps registered state and opens Book List directly | Partial: P01 - DEVICE-UNIT-002/003 @ `test/app/unit/repositories/device/device_repository_impl_test.dart`; P10 - APP-WIDGET-001 @ `test/widget_test.dart` |

## 2. Book Behavior

| Done | Auto Test | Operation | Expected Behavior | Trace |
|---|---|---|---|---|
| [V] | [V] | Create a new book with valid name | New book appears in active book list | P02 - BOOK-UNIT-004 @ `test/app/unit/repositories/book/book_repository_impl_create_test.dart`; P12 - EVENT-INTEG-007 @ `test/app/integration/event_metadata/event_integ_007_book_contract_test.dart` |
| [V] | [V] | Try to create book with blank name | Book is not created; validation feedback is shown | P02 - BOOK-UNIT-004/015 @ `test/app/unit/repositories/book/book_repository_impl_create_test.dart` |
| [X] | [V] | Rename a book (with extra spaces before/after name) | Name is saved and displayed trimmed | P04 - BOOK-UNIT-006/013 @ `test/app/unit/repositories/book/book_repository_impl_update_test.dart`; P12 - EVENT-INTEG-007 @ `test/app/integration/event_metadata/event_integ_007_book_contract_test.dart` |
| [ ] | [V] | Archive a book | Book disappears from active list (not shown as active) | P03 - BOOK-UNIT-002 @ `test/app/unit/repositories/book/book_repository_impl_write_test.dart`; P12 - EVENT-INTEG-007 @ `test/app/integration/event_metadata/event_integ_007_book_contract_test.dart` |
| [V] | [V] | Delete a book | Book is removed and no longer appears in list | P03 - BOOK-UNIT-002/014 @ `test/app/unit/repositories/book/book_repository_impl_write_test.dart`; P12 - EVENT-INTEG-007 @ `test/app/integration/event_metadata/event_integ_007_book_contract_test.dart` |
| [V] | [V] | Reorder books by drag/drop, then relaunch app | Order persists after relaunch | P04 @ `test/app/unit/services/book/book_order_service_test.dart` |
| [V] | [V] | Open import-from-server flow, search by keyword, pull one book | Search result appears; imported book is added locally | P04 - BOOK-UNIT-009/012/013/014 @ `test/app/unit/repositories/book/book_repository_impl_server_test.dart`; P12 - EVENT-INTEG-007 @ `test/app/integration/event_metadata/event_integ_007_book_contract_test.dart` |
| [ ] | [V] | Try pulling a book with wrong password | Server rejects import and app does not add the book locally | P12 - EVENT-INTEG-007 @ `test/app/integration/event_metadata/event_integ_007_book_contract_test.dart`; BOOK-WIDGET-001 @ `test/app/widget/book_list_import_popup_test.dart` |
| [V] | [V] | Try pulling a book that already exists locally | App blocks duplicate import with clear message | P04 - BOOK-UNIT-011 @ `test/app/unit/repositories/book/book_repository_impl_server_test.dart`; BOOK-WIDGET-002 @ `test/app/widget/book_list_import_popup_test.dart` |
| [ ] | [V] | (If read-only device/book role exists) try creating or modifying a book | Server rejects create/rename/archive/delete actions and book state stays unchanged | P12 - EVENT-INTEG-007 @ `test/app/integration/event_metadata/event_integ_007_book_contract_test.dart` |

## 3. Event Behavior

| Done | Auto Test | Operation | Expected Behavior | Trace |
|---|---|---|---|---|
| [V] | [V] | In a selected book, create an event in schedule | Event appears at chosen time slot | P05 - EVENT-UNIT-004 @ `test/app/unit/repositories/event/event_repository_impl_write_test.dart` |
| [V] | [V] | Edit event title/type and save | Updated values persist after reopening event | P05 - EVENT-UNIT-005 @ `test/app/unit/repositories/event/event_repository_impl_write_test.dart`; P12 - EVENT-INTEG-001 @ `test/app/integration/event_metadata/event_integ_001_metadata_update_test.dart` |
| [ ] | [V] | Remove event with reason | Event is marked removed (not active in normal schedule flow) | P05 - EVENT-UNIT-007 @ `test/app/unit/repositories/event/event_repository_impl_write_test.dart` |
| [ ] | [V] | Change event time (reschedule) | Event appears at new slot; old slot no longer active | P05 - EVENT-UNIT-008 @ `test/app/unit/repositories/event/event_repository_impl_write_test.dart`; P12 - EVENT-INTEG-014 @ `test/app/integration/event_metadata/event_integ_014_schedule_reschedule_pipeline_test.dart` |
| [ ] | [V] | Delete event permanently | Event is fully removed and cannot be reopened | P05 - EVENT-UNIT-006 @ `test/app/unit/repositories/event/event_repository_impl_write_test.dart` |
| [ ] | [V] | Enter an existing record number while editing event details | Canonical record data loads from server and the shared note resolves for that record | P12 - EVENT-INTEG-013 @ `test/app/integration/event_metadata/event_integ_013_record_lookup_autofill_test.dart`; P09 - EVENT-DETAIL-UNIT-017/018 @ `test/app/unit/controllers/event_detail_controller_test.dart` |
| [ ] | [V] | On two write devices, edit the same record metadata and save both | Latest server write is the final value shown after refresh | P12 - EVENT-INTEG-011 @ `test/app/integration/event_metadata/event_integ_011_multi_device_metadata_lww_test.dart` |
| [ ] | [V] | (If read-only device/book role exists) try creating, editing, or rescheduling an event | Server rejects the write and the existing event state remains unchanged | P12 - EVENT-INTEG-001/002/003/004/006 @ `test/app/integration/event_metadata/` |
| [ ] | [ ] | Navigate across day range/week and return | Event rendering stays consistent with date filter | Manual only |

## 4. Note Behavior

| Done | Auto Test | Operation | Expected Behavior | Trace |
|---|---|---|---|---|
| [ ] | [V] | Open Event Detail note and write strokes, then save | Note content persists when reopening same event | P09 - EVENT-FLOW-001 @ `test/app/unit/controllers/event_detail_controller_test.dart`; P12 - EVENT-INTEG-008 @ `test/app/integration/event_metadata/event_integ_008_note_contract_test.dart` |
| [ ] | [V] | Open another event with same record/person | Same shared note content is shown (record-based note) | P07 - NOTE-UNIT-001 @ `test/app/unit/repositories/note/note_repository_impl_test.dart`; P12 - EVENT-INTEG-008 @ `test/app/integration/event_metadata/event_integ_008_note_contract_test.dart` |
| [ ] | [V] | Create event for record that already has note, but do not write/update note and save | Event does not show note tag; note tag appears only on events that actually create/update note | P09 - EVENT-DETAIL-UNIT-005 @ `test/app/unit/controllers/event_detail_controller_test.dart`; P12 - EVENT-INTEG-003 @ `test/app/integration/event_metadata/event_integ_003_has_note_scope_test.dart` |
| [ ] | [V] | Create no-record-number event with handwriting note, then reschedule time and open old/new events | Both old (cancelled) and new event show the same shared handwriting note | P05 - EVENT-UNIT-009 @ `test/app/unit/repositories/event/event_repository_impl_write_test.dart`; P12 - EVENT-INTEG-002 @ `test/app/integration/event_metadata/event_integ_002_no_record_reschedule_test.dart` |
| [ ] | [V] | Create no-record-number event, draw note and auto-save, then reenter and fill record number | Event is updated with the filled record number and handwriting note remains readable | P09 - EVENT-DETAIL-UNIT-010 @ `test/app/unit/controllers/event_detail_controller_test.dart`; P12 - EVENT-INTEG-004 @ `test/app/integration/event_metadata/event_integ_004_refill_record_number_test.dart` |
| [ ] | [V] | Edit note again and save | New strokes persist and previous content remains valid | P07 - NOTE-UNIT-002 @ `test/app/unit/repositories/note/note_repository_impl_test.dart`; P12 - EVENT-INTEG-008 @ `test/app/integration/event_metadata/event_integ_008_note_contract_test.dart` |
| [ ] | [V] | (If note clear/delete action exists) clear note cache/content | Note is removed/cleared and not shown on reopen | P07 - NOTE-UNIT-003 @ `test/app/unit/repositories/note/note_repository_impl_test.dart`; P12 - EVENT-INTEG-008 @ `test/app/integration/event_metadata/event_integ_008_note_contract_test.dart` |
| [ ] | [V] | (If read-only device/book role exists) try editing or deleting a shared note | Server rejects the change and the existing shared note remains visible | P12 - EVENT-INTEG-008 @ `test/app/integration/event_metadata/event_integ_008_note_contract_test.dart` |
| [ ] | [V] | On a write-role device after pulling a shared book, edit the shared note and save | The original device sees the updated note after refresh | P12 - EVENT-INTEG-008B @ `test/app/integration/event_metadata/event_integ_008_note_contract_test.dart` |
| [ ] | [V] | On two write devices, save the same shared note from stale versions | Stale save is rejected, newer server note remains visible, and retry with latest version succeeds | P12 - EVENT-INTEG-012 @ `test/app/integration/event_metadata/event_integ_012_multi_device_note_conflict_resolution_test.dart` |

## 5. Drawing Behavior (Schedule Overlay)

| Done | Auto Test | Operation | Expected Behavior | Trace |
|---|---|---|---|---|
| [ ] | [V] | Draw on schedule overlay, leave screen, return to same date | Drawing persists and reloads correctly | P08 - DRAWING-UNIT-001 @ `test/app/unit/repositories/drawing/drawing_repository_impl_test.dart`; P12 - EVENT-INTEG-009 @ `test/app/integration/event_metadata/event_integ_009_drawing_contract_test.dart` |
| [ ] | [V] | Update existing drawing on same date | Latest drawing content replaces previous version | P08 - DRAWING-UNIT-002/005 @ `test/app/unit/repositories/drawing/drawing_repository_impl_test.dart`; P12 - EVENT-INTEG-009 @ `test/app/integration/event_metadata/event_integ_009_drawing_contract_test.dart` |
| [ ] | [V] | Switch date and return | Drawing is tied to correct date and does not leak to other dates | P08 - DRAWING-UNIT-004 @ `test/app/unit/repositories/drawing/drawing_repository_impl_test.dart`; P12 - EVENT-INTEG-009 @ `test/app/integration/event_metadata/event_integ_009_drawing_contract_test.dart` |
| [ ] | [V] | In 2-day mode, draw on one page, navigate to previous page, then return | Drawing stays on the original 2-day page and does not appear on the previous page | P08 - SCHEDULE-UTIL-001/002 @ `test/app/unit/utils/schedule/schedule_layout_utils_test.dart` |
| [ ] | [V] | (If clear action exists) clear drawing for date | Drawing is removed for that date/view | P08 - DRAWING-UNIT-003 @ `test/app/unit/repositories/drawing/drawing_repository_impl_test.dart`; P12 - EVENT-INTEG-009 @ `test/app/integration/event_metadata/event_integ_009_drawing_contract_test.dart` |
| [ ] | [V] | (If read-only device/book role exists) pull a shared book, open its drawing, then try editing it | Existing shared drawing is visible, but save is blocked for the read-only device | P12 - EVENT-INTEG-009B @ `test/app/integration/event_metadata/event_integ_009_drawing_contract_test.dart` |
| [ ] | [V] | On a write-role device after pulling a shared book, edit the shared drawing and save | The original device sees the updated drawing after refresh | P12 - EVENT-INTEG-009C @ `test/app/integration/event_metadata/event_integ_009_drawing_contract_test.dart` |

## 6. Charge Item Behavior

| Done | Auto Test | Operation | Expected Behavior | Trace |
|---|---|---|---|---|
| [ ] | [V] | Create an event for a record that already has charge items | Existing record charge items remain linked, but the new event does not show has-charge-items yet | P12 - EVENT-INTEG-015A @ `test/app/integration/event_metadata/event_integ_015_charge_item_flag_test.dart` |
| [ ] | [V] | Add a charge item to an existing event | Charge item is linked to that event and the event shows has-charge-items after refresh | P12 - EVENT-INTEG-015B @ `test/app/integration/event_metadata/event_integ_015_charge_item_flag_test.dart`; P09 - EVENT-DETAIL-UNIT-022/026 @ `test/app/unit/controllers/event_detail_controller_test.dart` |
| [ ] | [V] | Append a paid item under a charge item | Existing paid items remain, the new paid item is appended after refresh, and a fully paid item reopens as 已付清 without duplicating the charge item | P12 - EVENT-INTEG-016 @ `test/app/integration/event_metadata/event_integ_016_charge_item_paid_update_test.dart`; P09 - EVENT-DETAIL-UNIT-013/028/032 @ `test/app/unit/controllers/event_detail_controller_test.dart` |

## 7. Device Credentials & Session

| Done | Auto Test | Operation | Expected Behavior | Trace |
|---|---|---|---|---|
| [ ] | [ ] | Complete setup once, then relaunch app multiple times | Credentials remain valid; app does not ask setup again | Partial: P01 - DEVICE-UNIT-002/003 @ `test/app/unit/repositories/device/device_repository_impl_test.dart`; P10 - APP-WIDGET-001 @ `test/widget_test.dart` |
| [ ] | [V] | Re-register / update device setup (if flow exists) | Latest credentials replace old state and app continues normally | P01 - DEVICE-UNIT-003 @ `test/app/unit/repositories/device/device_repository_impl_test.dart`; P12 - EVENT-INTEG-010 @ `test/app/integration/event_metadata/event_integ_010_device_session_contract_test.dart` |

## 8. Offline / Online Server Connectivity

| Done | Auto Test | Operation | Expected Behavior | Trace |
|---|---|---|---|---|
| [ ] | [V] | Turn on airplane mode, try create/edit book/event/note | Write is blocked with clear online-required message | P09 - EVENT-FLOW-002 @ `test/app/unit/controllers/event_detail_controller_test.dart` |
| [ ] | [V] | Re-enable network and retry same operation | Operation succeeds without duplicate objects | P09 - EVENT-FLOW-001/002 @ `test/app/unit/controllers/event_detail_controller_test.dart` |
| [ ] | [V] | Pull server data after reconnect | Pulled data merges cleanly with local state | Partial: P12 - EVENT-INTEG-006 @ `test/app/integration/event_metadata/event_integ_005_server_only_contract_test.dart` |

## 9. Performance Sanity (Manual)

| Done | Auto Test | Operation | Expected Behavior | Trace |
|---|---|---|---|---|
| [ ] | [ ] | Cold launch app on physical device | Startup is responsive; no long freeze or ANR | Manual only |
| [ ] | [ ] | Open book with dense schedule and scroll/navigate | Interactions remain smooth; no severe frame drops | Manual only |
| [ ] | [ ] | Open note/drawing-heavy screen and edit | Input latency is acceptable; no stutter/crash | Manual only |

## Defect Logging

| ID | Group | Operation | Actual Result | Expected Result | Severity | Screenshot/Video |
|---|---|---|---|---|---|---|
|  |  |  |  |  |  |  |
