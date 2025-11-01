# Phase 5: Screen Refactoring

**Duration:** Week 5-6
**Risk Level:** Low
**Dependencies:** Phase 4 complete

## Objective

Break down large screens (ScheduleScreen: 2,500 lines, EventDetailScreen: 1,000 lines, BookListScreen: 800 lines) into smaller, focused components. Replace setState() with BLoC/Cubit state management.

## Checklist

### Refactor BookListScreen

- [ ] Create `lib/screens/book_list/book_list_screen.dart`
- [ ] Wrap with BlocProvider for BookListCubit
- [ ] Replace setState() with BlocBuilder
- [ ] Extract widget: `book_list_item.dart`
- [ ] Extract widget: `create_book_dialog.dart`
- [ ] Extract widget: `delete_book_confirmation.dart`
- [ ] Remove direct database service access
- [ ] Remove service initialization logic
- [ ] Target: <300 lines for main screen

### Refactor ScheduleScreen

- [ ] Create `lib/screens/schedule/schedule_screen.dart`
- [ ] Wrap with BlocProvider for ScheduleCubit
- [ ] Replace setState() with BlocBuilder
- [ ] Extract widget: `schedule_header.dart` (date selector, book info)
- [ ] Extract widget: `event_list.dart` (list of events for selected date)
- [ ] Extract widget: `event_list_item.dart` (individual event card)
- [ ] Extract widget: `drawing_overlay.dart` (handwriting overlay)
- [ ] Extract widget: `sync_status_indicator.dart` (online/offline/syncing status)
- [ ] Extract widget: `create_event_dialog.dart`
- [ ] Remove direct service initialization
- [ ] Remove network monitoring logic (use NetworkCubit)
- [ ] Target: <400 lines for main screen, <150 lines per widget

### Refactor EventDetailScreen

- [ ] Create `lib/screens/event_detail/event_detail_screen.dart`
- [ ] Wrap with BlocProvider for EventDetailCubit
- [ ] Replace setState() with BlocBuilder
- [ ] Extract widget: `event_info_card.dart` (event details display)
- [ ] Extract widget: `event_edit_form.dart` (edit mode form)
- [ ] Extract widget: `note_editor.dart` (handwriting canvas wrapper)
- [ ] Extract widget: `note_toolbar.dart` (save/clear/undo buttons)
- [ ] Remove direct service initialization
- [ ] Remove network monitoring logic
- [ ] Target: <350 lines for main screen, <150 lines per widget

### Create Shared Widgets Directory

- [ ] Create `lib/widgets/common/` directory
- [ ] Move reusable widgets: `error_message.dart`
- [ ] Move reusable widgets: `loading_indicator.dart`
- [ ] Move reusable widgets: `empty_state.dart`
- [ ] Move reusable widgets: `sync_badge.dart`

### Update Navigation

- [ ] Review navigation logic
- [ ] Ensure cubit state doesn't leak between screens
- [ ] Pass only necessary data (IDs, not full objects)
- [ ] Ensure proper disposal of resources

### Update Error Handling

- [ ] Create `lib/utils/error_handler.dart`
- [ ] Centralize SnackBar/Dialog error display
- [ ] Use from all screens consistently
- [ ] Remove duplicated error handling code

## Testing

### Widget Tests Required

**File:** `test/screens/book_list_screen_test.dart`
- Screen renders correctly
- BlocProvider provides cubit
- BlocBuilder updates on state changes
- Create book button works
- Delete book confirmation shows
- Navigation to schedule screen works

**File:** `test/screens/schedule_screen_test.dart`
- Screen renders correctly
- Date selector works
- Event list displays correctly
- Create event dialog works
- Navigation to event detail works
- Drawing overlay toggles correctly
- Sync status indicator reflects state

**File:** `test/screens/event_detail_screen_test.dart`
- Screen renders correctly
- Event info displays correctly
- Edit mode toggles
- Note editor works
- Save button triggers cubit
- Delete button shows confirmation

**File:** `test/widgets/event_list_test.dart`
- Displays empty state when no events
- Displays events correctly
- Tap event navigates correctly

**File:** `test/widgets/drawing_overlay_test.dart`
- Overlay shows/hides correctly
- Drawing saves on close
- Clear button works

### Integration Tests Required

**File:** `test/integration/screen_flow_test.dart`
- Book list → Schedule → Event detail flow
- Create book → create event → add note flow
- Edit event flow
- Delete event flow

### Manual Testing

- [ ] Book list screen: create, delete, reorder books
- [ ] Schedule screen: view events, change dates, add drawings
- [ ] Event detail screen: view, edit, add notes
- [ ] Offline mode: all screens work without network
- [ ] Error cases: API errors show friendly messages
- [ ] Navigation: back buttons work correctly
- [ ] State: no memory leaks, proper cleanup

## Definition of Done

- [ ] BookListScreen refactored (<300 lines)
- [ ] ScheduleScreen refactored (<400 lines)
- [ ] EventDetailScreen refactored (<350 lines)
- [ ] All widgets extracted and organized
- [ ] All screens use BLoC pattern
- [ ] No direct service initialization in screens
- [ ] Error handling centralized
- [ ] All widget tests passing
- [ ] Integration tests passing
- [ ] Manual testing complete
- [ ] No behavior changes from user perspective

## Rollback Plan

If issues arise:
1. Keep old screens in `lib/screens/legacy_*` temporarily
2. Switch back to old screens in routing
3. Debug new screens separately
4. Re-enable when stable

## Notes

- Focus on extracting widgets first, then wiring cubits
- Each widget should have a single responsibility
- Keep widget files small (<150 lines)
- Test widgets in isolation
- Use const constructors where possible for performance
- Avoid rebuilding entire screen - use targeted BlocBuilders
- Remember: UI should be dumb - all logic in cubits
