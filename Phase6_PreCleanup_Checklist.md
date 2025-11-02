# Phase 6 - Pre-Cleanup Verification Checklist

**CRITICAL**: Complete this checklist BEFORE proceeding to Phase 7 (cleanup).
Phase 7 will remove the old backup code, so we must verify cubit works 100% correctly.

---

## 🔍 How to Test

Watch for debug messages in the console:
- `🔷 PHASE2: Cubit loaded X events` - Confirms cubit is loading events
- `✅ ScheduleCubit: Loaded X events for 3-day window` - Confirms 3-day window logic

---

## ✅ Critical Features to Verify

### 1. Event Display & Loading
- [ ] **Events appear on schedule** - Events display in the 3-day view
- [ ] **Correct 3-day window** - Events for all 3 days are visible
- [ ] **Loading indicator works** - Shows while loading events
- [ ] **No duplicate events** - Each event appears only once

**How to test:**
1. Open a book with existing events
2. Verify all events in the current 3-day window appear
3. Check console: Should see `Loaded X events for 3-day window starting YYYY-MM-DD`

---

### 2. Date Navigation
- [ ] **Previous button** - Loads previous 3-day window correctly
- [ ] **Next button** - Loads next 3-day window correctly
- [ ] **Date picker** - Selecting a date loads correct 3-day window
- [ ] **Go to today button** - Jumps to today's 3-day window

**How to test:**
1. Click Previous/Next arrows
2. Verify events update to show the new 3-day window
3. Use date picker to jump to a specific date
4. Click "Go to Today" button
5. Check console for `Cubit loaded X events` messages

---

### 3. Event CRUD Operations

#### Create Event
- [ ] **Create new event** - Event appears immediately after creation
- [ ] **Correct position** - Event shows in correct date/time slot
- [ ] **Cubit reloads** - Console shows cubit reloaded events

**How to test:**
1. Tap on a time slot to create event
2. Fill in event details and save
3. Verify event appears immediately
4. Check console: `Cubit loaded X events`

#### Update Event
- [ ] **Edit event name** - Changes appear immediately
- [ ] **Change event type** - Color changes immediately
- [ ] **Change event time** - Event moves to new time slot

**How to test:**
1. Tap on an existing event
2. Change name/type/time
3. Save and verify changes appear
4. Check console: `Cubit loaded X events`

#### Delete Event
- [ ] **Soft delete (remove)** - Event becomes translucent with strikethrough
- [ ] **Hard delete** - Event disappears completely
- [ ] **Cubit reloads** - Console shows cubit reloaded events

**How to test:**
1. Long-press an event to open context menu
2. Try "Remove from schedule" (soft delete)
3. Try "Delete permanently" (hard delete)
4. Verify behavior matches old version

---

### 4. Old Events Toggle
- [ ] **Toggle ON** - All events visible (including removed/time-changed)
- [ ] **Toggle OFF** - Removed and old time-changed events hidden
- [ ] **Icon updates** - Eye icon changes to reflect state
- [ ] **Cubit filters correctly** - Console shows filtered event count

**How to test:**
1. Create an event, then remove it (soft delete)
2. Click the eye icon in AppBar
3. Verify removed event disappears
4. Click eye icon again
5. Verify removed event reappears (translucent)
6. Check console: `Cubit loaded X events`

---

### 5. Drawing Operations
- [ ] **Drawing appears** - Existing drawing loads when entering 3-day window
- [ ] **Drawing persists** - Drawing saves after strokes
- [ ] **Clear drawing** - Clearing removes all strokes
- [ ] **Date navigation** - Drawing changes when navigating to different page

**How to test:**
1. Enter drawing mode
2. Draw some strokes
3. Exit drawing mode
4. Navigate to different date and back
5. Verify drawing reappears correctly

---

### 6. Offline/Online Status
- [ ] **Offline indicator** - Shows when server unreachable
- [ ] **Online indicator** - Shows when server reachable
- [ ] **Cubit tracks status** - Console logs offline status changes

**How to test:**
1. Stop the server (if running)
2. Wait for offline indicator to appear
3. Start the server again
4. Verify online indicator appears

---

## 🐛 Known Issues

### Issue 1: Toggle Old Events Behavior
**Current behavior:** Clicking toggle causes events to reload (brief flicker)
**Expected behavior:** Events filter instantly without reload
**Severity:** Low (minor UX issue, not breaking)
**Fix needed?** Optional - can optimize in Phase 7 if desired

---

## 📊 Test Results

Date tested: __________
Tested by: __________

### Summary
- [ ] All critical features work correctly
- [ ] No regressions from old behavior
- [ ] UI responds correctly to cubit state changes
- [ ] No console errors or warnings
- [ ] Ready for Phase 7 cleanup

### Notes:
```
(Record any issues or observations here)




```

---

## 🚨 If Tests Fail

**DO NOT proceed to Phase 7!**

1. Document the failing test case
2. Check console for error messages
3. Compare behavior with old version (old code is still running in parallel)
4. Report the issue for investigation and fix

---

## ✅ Sign-Off

Once all tests pass:
- [ ] Verified by user (manual testing complete)
- [ ] No behavior regressions
- [ ] Console shows correct cubit state changes
- [ ] Ready to proceed to Phase 7

**Approved by:** ________________  **Date:** __________
