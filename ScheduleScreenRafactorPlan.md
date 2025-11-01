ScheduleScreen Refactoring - Remaining Phases

  ✅ Phase 0: Critical Behavior Tests (COMPLETE)

  - Created characterization tests (4/4 passing)
  - Tests capture critical behavior before refactoring
  - Acts as safety net to detect regressions

  ✅ Phase 1: BLoC Infrastructure (COMPLETE)

  - Added BlocProvider wrapper to ScheduleScreen
  - Added imports for flutter_bloc, ScheduleCubit, ScheduleState
  - Zero code changes to ScheduleScreen logic
  - Old code still handles everything

  ✅ Phase 2: Event Loading - Parallel Run (COMPLETE)

  - Fixed GetIt registration for ScheduleCubit
  - Cubit initializes and loads events in parallel
  - Added BlocListener to monitor cubit state
  - Old code still renders UI - using _events state variable
  - Both systems run together, old code still active

  ✅ Phase 3: Event CRUD - Parallel Run (COMPLETE)

  Goal: Cubit handles create/update/delete in parallel with old code

  Changes made:
  1. ✅ Added cubit.loadEvents() after _createEvent() returns from EventDetailScreen
  2. ✅ Added cubit.loadEvents() after _editEvent() returns from EventDetailScreen
  3. ✅ Added cubit.updateEvent() in _changeEventType() (parallel with old updateEvent)
  4. ✅ Added cubit.deleteEvent() in _removeEventFromSchedule() (soft delete with reason)
  5. ✅ Added cubit.loadEvents() in _deleteEventFromSchedule() (hard delete reload)
  6. ✅ Added cubit.loadEvents() in _changeEventTimeFromSchedule() (reload after time change)

  Files modified:
  - lib/screens/schedule_screen.dart (6 methods updated with cubit calls)

  Known limitations (TODO for future):
  - Hard delete: Cubit only has soft delete, using loadEvents() for now
  - Change event time: Cubit doesn't have changeEventTime(), using loadEvents() for now

  Actual lines changed: ~30 lines (added cubit calls, all old code still active)

  Validation:
  - ✅ Code compiles without errors
  - ⏳ Create event → User should test both old list and cubit state update
  - ⏳ Update event type → User should test both systems reflect changes
  - ⏳ Remove event → User should test both systems soft-delete event
  - ⏳ Delete event → User should test both systems remove event

  ---
  🔜 Remaining Phases (Parallel Run Strategy)

  ✅ Phase 4: Drawing - Parallel Run (COMPLETE)

  Goal: Cubit handles drawing load/save in parallel with old code

  Changes made:
  1. ✅ Added cubit.loadDrawing() in _loadDrawing() after setting _currentDrawing state
  2. ✅ Added cubit.saveDrawing() in _saveDrawing() (both ContentService and cache-only paths)
  3. ✅ Cubit mirrors drawing state alongside old _currentDrawing variable

  Files modified:
  - lib/screens/schedule_screen.dart (2 methods updated with cubit calls)

  Implementation details:
  - Load: Cubit loads drawing after old code sets state (viewMode: 1 for 3-day view)
  - Save: Cubit saves drawing after old code persists to database/server
  - Clear: Handled automatically via save (empty strokes array)
  - Both paths (ContentService + cache-only fallback) call cubit

  Actual lines changed: ~8 lines (added cubit calls, all old code still active)

  Validation:
  - ✅ Code compiles without errors
  - ⏳ Enter drawing mode → User should test drawing loads correctly
  - ⏳ Draw strokes → User should test auto-save works (debounced 500ms)
  - ⏳ Exit drawing mode → User should test drawing saves to both systems
  - ⏳ Clear drawing → User should test empty drawing saves correctly

  ---

  ✅ Phase 5: Date Navigation & UI State - Parallel Run (COMPLETE)

  Goal: Cubit manages date selection and UI state

  Changes made:
  1. ✅ Added cubit.selectDate() in all date navigation controls (8 locations)
     - Previous/Next buttons (date navigation arrows)
     - Date picker (tap on date display)
     - Go to today button (appbar icon)
     - Go to today FAB (floating action button)
     - Auto date change detection (midnight rollover)
     - Reset to real time (debugging feature)
     - Set test time (debugging feature)
  2. ✅ Added cubit.toggleOldEvents() in toggle old events button
  3. ✅ Added cubit.setOfflineStatus() in all offline status updates (3 locations)
     - Initial connectivity check
     - Periodic connectivity monitoring
     - ContentService initialization failure

  Files modified:
  - lib/screens/schedule_screen.dart (12 locations updated with cubit calls)

  Implementation details:
  - Date changes: All date updates call cubit.selectDate() after setState()
  - Old events toggle: Toggles both old state and cubit state synchronously
  - Offline status: All connectivity changes update both old state and cubit
  - Old state variables remain active and control UI rendering

  Actual lines changed: ~40 lines (added cubit calls, all old code still active)

  Validation:
  - ✅ Code compiles without errors
  - ⏳ Navigate dates (prev/next arrows) → Test both states update
  - ⏳ Pick date from calendar → Test both states update
  - ⏳ Go to today → Test both states update
  - ⏳ Toggle old events visibility → Test filtering works
  - ⏳ Offline/online transitions → Test both states track connectivity

  **Bug Fix Applied (Post-Phase 5):**
  - 🐛 Fixed "go to today" button not reloading drawing when page changes
    - AppBar version: Removed `if (_isDrawingMode)` check, now always loads drawing
    - FAB version: Added `await` to `_loadDrawing()` call
    - Both now match the working behavior of prev/next arrows and date picker
    - Files modified: lib/screens/schedule_screen.dart (lines 2880, 2955)

  ---

  ---

  ✅ Phase 6: Switch to Cubit Rendering (COMPLETE)

  Goal: UI uses cubit state instead of old state variables

  Changes made:
  1. ✅ Wrapped Scaffold body in BlocBuilder<ScheduleCubit, ScheduleState>
  2. ✅ Extract events, isLoading, showOldEvents from cubit state
  3. ✅ Updated method signatures to accept events and showOldEvents as parameters:
     - _build3DayView(List<Event> events, bool showOldEvents)
     - _buildTimeSlotView(..., List<Event> events, bool showOldEvents)
     - _buildEventsOverlay(..., List<Event> events, bool showOldEvents)
     - _getEventsForDate(DateTime date, List<Event> events, bool showOldEvents)
     - _getNewEventForTimeChange(Event event, List<Event> events)
     - _buildEventContextMenuOverlay(List<Event> events)
     - _buildEventTile(BuildContext context, Event event, double slotHeight, List<Event> events)
     - _buildEventTileContent(Event event, double tileHeight, double slotHeight, List<Event> events)
  4. ✅ Removed unused state variable: _isLoading
  5. ✅ Kept backup state variables for now (will remove in Phase 7):
     - _events (still used by preloading logic)
     - _showOldEvents (still used by AppBar toggle button, outside BlocBuilder)

  Files modified:
  - lib/screens/schedule_screen.dart (body wrapped in BlocBuilder, 8 methods updated)

  Implementation details:
  - UI now reads from cubit state (state.events, state.showOldEvents)
  - Loading indicator uses state is ScheduleLoading
  - Old _loadEvents() still runs in parallel as backup
  - AppBar toggle button still uses _showOldEvents (outside BlocBuilder scope)

  Actual lines changed: ~50 lines (added BlocBuilder, updated method signatures)

  Validation:
  - ✅ Code compiles without errors (51 info/warnings, all pre-existing)
  - ✅ Critical behavior tests pass (4/4)
  - ⚠️ Full test suite has database initialization issue (pre-existing, not caused by refactoring)
  - ⏳ Manual testing → User should verify zero behavior change
  - ⏳ Compare screenshots → User should verify identical UI

  ---
  Phase 7: Final Cleanup

  Goal: Remove old code only after verification

  Changes:
  1. Remove commented old code
  2. Remove unused state variables
  3. Remove unused imports
  4. Clean up TODOs and debug prints

  Files to modify:
  - lib/screens/schedule_screen.dart - Remove old code

  Validation:
  - Final test suite run → All tests pass
  - Code review → Verify no dead code remains
  - Line count reduction → ~4,088 → ~500 lines (ScheduleScreen becomes much smaller)

  Estimated lines removed: ~3,500 lines

  ---
  Summary Table

  | Phase               | Status     | Old Code Active? | Cubit Active?    | Risk Level |
  |---------------------|------------|------------------|------------------|------------|
  | 0: Tests            | ✅ Complete | N/A              | N/A              | None       |
  | 1: Infrastructure   | ✅ Complete | ✅ Yes            | ⚠️ Initialized   | None       |
  | 2: Event Loading    | ✅ Complete | ✅ Yes            | ✅ Yes (parallel) | Low        |
  | 3: Event CRUD       | ✅ Complete | ✅ Yes            | ✅ Yes (parallel) | Low        |
  | 4: Drawing          | ✅ Complete | ✅ Yes            | ✅ Yes (parallel) | Low        |
  | 5: UI State         | ✅ Complete | ✅ Yes            | ✅ Yes (parallel) | Low        |
  | 6: Switch Rendering | ✅ Complete | ⚠️ Backup only   | ✅ Primary        | Medium     |
  | 7: Cleanup          | 🔜 Next    | ❌ To be removed  | ✅ Only           | Low        |