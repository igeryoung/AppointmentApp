# Physical Device Test Checklist

Use this checklist for real-device verification after unit tests pass.

## Automation Reference

- Ordered automated pipeline runner:
  - `/Users/yangping/Studio/side-project/scheduleNote/tool/test_user_pipeline.sh`
- Automation guide:
  - `/Users/yangping/Studio/side-project/scheduleNote/docs/testing/user_pipeline_automation.md`
- Latest run reports:
  - `/Users/yangping/Studio/side-project/scheduleNote/docs/testing/reports/`

## Test Session Info

| Field | Value |
|---|---|
| Date | |
| Device Model / OS | |
| App Build (git commit / version) | |
| Server URL | |
| Tester | |

## 1. App Launch & Setup

| Done | Auto Test | Operation | Expected Behavior |
|---|---|---|---|
| [V] | [ ] | Install app fresh (clear old app data), then open app | App starts without crash and enters setup flow when no device credentials exist |
| [V] | [ ] | Enter invalid server URL / unreachable server and continue | App shows setup failure and does not proceed to book list |
| [V] | [V] | Register device with valid server config | Setup succeeds and app navigates to Book List |
| [V] | [ ] | Force close app and reopen | App keeps registered state and opens Book List directly |

## 2. Book Behavior

| Done | Auto Test | Operation | Expected Behavior |
|---|---|---|---|
| [V] | [ ] | Create a new book with valid name | New book appears in active book list |
| [V] | [ ] | Try to create book with blank name | Book is not created; validation feedback is shown |
| [X] | [ ] | Rename a book (with extra spaces before/after name) | Name is saved and displayed trimmed |
| [ ] | [ ] | Archive a book | Book disappears from active list (not shown as active) |
| [V] | [ ] | Delete a book | Book is removed and no longer appears in list |
| [Ｖ] | [ ] | Reorder books by drag/drop, then relaunch app | Order persists after relaunch |
| [Ｖ] | [ ] | Open import-from-server flow, search by keyword, pull one book | Search result appears; imported book is added locally |
| [Ｖ] | [ ] | Try pulling a book that already exists locally | App blocks duplicate import with clear message |

## 3. Event Behavior

| Done | Auto Test | Operation | Expected Behavior |
|---|---|---|---|
| [V] | [ ] | In a selected book, create an event in schedule | Event appears at chosen time slot |
| [ ] | [ ] | Edit event title/type and save | Updated values persist after reopening event |
| [ ] | [ ] | Remove event with reason | Event is marked removed (not active in normal schedule flow) |
| [ ] | [ ] | Change event time (reschedule) | Event appears at new slot; old slot no longer active |
| [ ] | [ ] | Delete event permanently | Event is fully removed and cannot be reopened |
| [ ] | [ ] | Navigate across day range/week and return | Event rendering stays consistent with date filter |

## 4. Note Behavior

| Done | Auto Test | Operation | Expected Behavior |
|---|---|---|---|
| [ ] | [ ] | Open Event Detail note and write strokes, then save | Note content persists when reopening same event |
| [ ] | [ ] | Open another event with same record/person | Same shared note content is shown (record-based note) |
| [ ] | [V] | Create no-record-number event with handwriting note, then reschedule time and open old/new events | Both old (cancelled) and new event show the same shared handwriting note |
| [ ] | [ ] | Edit note again and save | New strokes persist and previous content remains valid |
| [ ] | [ ] | (If note clear/delete action exists) clear note cache/content | Note is removed/cleared and not shown on reopen |

## 5. Drawing Behavior (Schedule Overlay)

| Done | Auto Test | Operation | Expected Behavior |
|---|---|---|---|
| [ ] | [ ] | Draw on schedule overlay, leave screen, return to same date | Drawing persists and reloads correctly |
| [ ] | [ ] | Update existing drawing on same date | Latest drawing content replaces previous version |
| [ ] | [ ] | Switch date and return | Drawing is tied to correct date and does not leak to other dates |
| [ ] | [ ] | (If clear action exists) clear drawing for date | Drawing is removed for that date/view |

## 6. Device Credentials & Session

| Done | Auto Test | Operation | Expected Behavior |
|---|---|---|---|
| [ ] | [ ] | Complete setup once, then relaunch app multiple times | Credentials remain valid; app does not ask setup again |
| [ ] | [ ] | Re-register / update device setup (if flow exists) | Latest credentials replace old state and app continues normally |

## 7. Offline / Online Server Connectivity

| Done | Auto Test | Operation | Expected Behavior |
|---|---|---|---|
| [ ] | [ ] | Turn on airplane mode, try create/edit book/event/note | Write is blocked with clear online-required message |
| [ ] | [ ] | Re-enable network and retry same operation | Operation succeeds without duplicate objects |
| [ ] | [V] | Pull server data after reconnect | Pulled data merges cleanly with local state |

## 8. Performance Sanity (Manual)

| Done | Auto Test | Operation | Expected Behavior |
|---|---|---|---|
| [ ] | [ ] | Cold launch app on physical device | Startup is responsive; no long freeze or ANR |
| [ ] | [ ] | Open book with dense schedule and scroll/navigate | Interactions remain smooth; no severe frame drops |
| [ ] | [ ] | Open note/drawing-heavy screen and edit | Input latency is acceptable; no stutter/crash |

## Defect Logging

| ID | Group | Operation | Actual Result | Expected Result | Severity | Screenshot/Video |
|---|---|---|---|---|---|---|
|  |  |  |  |  |  |  |
