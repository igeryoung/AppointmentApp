# Physical Device Test Checklist

Use this checklist for real-device verification after unit tests pass.

## Test Session Info

| Field | Value |
|---|---|
| Date | |
| Device Model / OS | |
| App Build (git commit / version) | |
| Server URL | |
| Tester | |

## 1. App Launch & Setup

| Done | Operation | Expected Behavior |
|---|---|---|
| [V] | Install app fresh (clear old app data), then open app | App starts without crash and enters setup flow when no device credentials exist |
| [V] | Enter invalid server URL / unreachable server and continue | App shows setup failure and does not proceed to book list |
| [V] | Register device with valid server config | Setup succeeds and app navigates to Book List |
| [V] | Force close app and reopen | App keeps registered state and opens Book List directly |

## 2. Book Behavior

| Done | Operation | Expected Behavior |
|---|---|---|
| [V] | Create a new book with valid name | New book appears in active book list |
| [V] | Try to create book with blank name | Book is not created; validation feedback is shown |
| [X] | Rename a book (with extra spaces before/after name) | Name is saved and displayed trimmed |
| [ ] | Archive a book | Book disappears from active list (not shown as active) |
| [ ] | Delete a book | Book is removed and no longer appears in list |
| [ ] | Reorder books by drag/drop, then relaunch app | Order persists after relaunch |
| [ ] | Open restore-from-server flow, search by keyword, pull one book | Search result appears; pulled book is added locally |
| [ ] | Try pulling a book that already exists locally | App blocks duplicate restore with clear message |

## 3. Event Behavior

| Done | Operation | Expected Behavior |
|---|---|---|
| [ ] | In a selected book, create an event in schedule | Event appears at chosen time slot |
| [ ] | Edit event title/type and save | Updated values persist after reopening event |
| [ ] | Remove event with reason | Event is marked removed (not active in normal schedule flow) |
| [ ] | Change event time (reschedule) | Event appears at new slot; old slot no longer active |
| [ ] | Delete event permanently | Event is fully removed and cannot be reopened |
| [ ] | Navigate across day range/week and return | Event rendering stays consistent with date filter |

## 4. Note Behavior

| Done | Operation | Expected Behavior |
|---|---|---|
| [ ] | Open Event Detail note and write strokes, then save | Note content persists when reopening same event |
| [ ] | Open another event with same record/person | Same shared note content is shown (record-based note) |
| [ ] | Edit note again and save | New strokes persist and previous content remains valid |
| [ ] | (If note clear/delete action exists) clear note cache/content | Note is removed/cleared and not shown on reopen |

## 5. Drawing Behavior (Schedule Overlay)

| Done | Operation | Expected Behavior |
|---|---|---|
| [ ] | Draw on schedule overlay, leave screen, return to same date | Drawing persists and reloads correctly |
| [ ] | Update existing drawing on same date | Latest drawing content replaces previous version |
| [ ] | Switch date and return | Drawing is tied to correct date and does not leak to other dates |
| [ ] | (If clear action exists) clear drawing for date | Drawing is removed for that date/view |

## 6. Device Credentials & Session

| Done | Operation | Expected Behavior |
|---|---|---|
| [ ] | Complete setup once, then relaunch app multiple times | Credentials remain valid; app does not ask setup again |
| [ ] | Re-register / update device setup (if flow exists) | Latest credentials replace old state and app continues normally |

## 7. Offline / Online & Sync Sanity

| Done | Operation | Expected Behavior |
|---|---|---|
| [ ] | Turn on airplane mode, create/edit local book/event/note | Local operations still work without crash |
| [ ] | Re-enable network and trigger sync path | Local changes sync without duplicate objects |
| [ ] | Pull server data after reconnect | Pulled data merges cleanly with local state |

## 8. Performance Sanity (Manual)

| Done | Operation | Expected Behavior |
|---|---|---|
| [ ] | Cold launch app on physical device | Startup is responsive; no long freeze or ANR |
| [ ] | Open book with dense schedule and scroll/navigate | Interactions remain smooth; no severe frame drops |
| [ ] | Open note/drawing-heavy screen and edit | Input latency is acceptable; no stutter/crash |

## Defect Logging

| ID | Group | Operation | Actual Result | Expected Result | Severity | Screenshot/Video |
|---|---|---|---|---|---|---|
|  |  |  |  |  |  |  |
