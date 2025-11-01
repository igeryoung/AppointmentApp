# Phase 4: State Management with BLoC

**Duration:** Week 4-5
**Risk Level:** Medium
**Dependencies:** Phase 3 complete

## Objective

Implement BLoC/Cubit pattern to separate business logic from UI. Move state management and service orchestration out of screens into testable Cubits.

## Checklist

### Create BookListCubit

- [ ] Create `lib/cubits/book_list_cubit.dart`
- [ ] Create `lib/cubits/book_list_state.dart`
- [ ] Inject BookRepository via constructor
- [ ] Methods: `loadBooks()`, `createBook()`, `deleteBook()`, `reorderBooks()`
- [ ] States: `BookListInitial`, `BookListLoading`, `BookListLoaded`, `BookListError`
- [ ] Handle errors gracefully
- [ ] Target: <150 lines

### Create ScheduleCubit

- [ ] Create `lib/cubits/schedule_cubit.dart`
- [ ] Create `lib/cubits/schedule_state.dart`
- [ ] Inject EventRepository, DrawingContentService
- [ ] Manage: selected date, events list, drawing overlay, sync status
- [ ] Methods: `loadEvents()`, `selectDate()`, `createEvent()`, `updateEvent()`, `deleteEvent()`, `saveDrawing()`, `loadDrawing()`
- [ ] States: `ScheduleInitial`, `ScheduleLoading`, `ScheduleLoaded`, `ScheduleError`
- [ ] Handle online/offline state
- [ ] Target: <250 lines

### Create EventDetailCubit

- [ ] Create `lib/cubits/event_detail_cubit.dart`
- [ ] Create `lib/cubits/event_detail_state.dart`
- [ ] Inject EventRepository, NoteContentService
- [ ] Manage: event details, note content, edit mode, sync status
- [ ] Methods: `loadEvent()`, `updateEvent()`, `loadNote()`, `saveNote()`, `deleteNote()`, `toggleEditMode()`
- [ ] States: `EventDetailInitial`, `EventDetailLoading`, `EventDetailLoaded`, `EventDetailError`
- [ ] Handle dirty state for unsaved changes
- [ ] Target: <200 lines

### Create NetworkCubit (Optional Helper)

- [ ] Create `lib/cubits/network_cubit.dart`
- [ ] Create `lib/cubits/network_state.dart`
- [ ] Monitor connectivity changes
- [ ] States: `NetworkOnline`, `NetworkOffline`
- [ ] Emit state changes for UI updates
- [ ] Target: <100 lines

### Register Cubits

- [ ] Update service_locator.dart
- [ ] Register as factories (not singletons)
- [ ] Ensure dependencies injected correctly

## Testing

### Unit Tests Required

**File:** `test/cubits/book_list_cubit_test.dart`
- Initial state is BookListInitial
- Load books emits Loading → Loaded
- Load books handles errors (emits Error state)
- Create book updates state correctly
- Delete book updates state correctly
- Reorder books updates state correctly

**File:** `test/cubits/schedule_cubit_test.dart`
- Initial state is ScheduleInitial
- Load events emits Loading → Loaded
- Select date loads events for that date
- Create event adds to state
- Update event modifies state
- Delete event removes from state
- Load drawing fetches from service
- Save drawing calls service correctly
- Handle offline mode (no API calls)

**File:** `test/cubits/event_detail_cubit_test.dart`
- Initial state is EventDetailInitial
- Load event emits Loading → Loaded
- Update event saves and updates state
- Load note fetches from service
- Save note calls service and updates state
- Delete note removes and updates state
- Toggle edit mode changes state
- Dirty state tracks unsaved changes

**File:** `test/cubits/network_cubit_test.dart`
- Initial state reflects current connectivity
- Emits NetworkOffline when connection lost
- Emits NetworkOnline when connection restored

### Integration Tests Required

**File:** `test/integration/cubit_integration_test.dart`
- BookListCubit → ScheduleCubit flow
- ScheduleCubit → EventDetailCubit flow
- Network changes affect cubit behavior

### Widget Tests Required

**File:** `test/widgets/book_list_with_cubit_test.dart`
- BlocProvider provides cubit correctly
- BlocBuilder rebuilds on state changes
- Error states show error messages

## Definition of Done

- [ ] BookListCubit created and tested
- [ ] ScheduleCubit created and tested
- [ ] EventDetailCubit created and tested
- [ ] NetworkCubit created and tested (if implemented)
- [ ] All cubits registered in service locator
- [ ] All unit tests passing (>80% coverage)
- [ ] Integration tests passing
- [ ] Widget tests passing
- [ ] Cubits are <250 lines each

## Rollback Plan

If issues arise:
1. Keep cubits but don't use in screens yet
2. Continue using setState() pattern temporarily
3. Debug cubit issues separately
4. Re-integrate when stable

## Notes

- Cubits should have NO UI logic - only business logic
- Cubits should be easily testable without widgets
- Use dependency injection for all services
- State classes should be immutable
- Use copyWith() pattern for state updates
- Don't put too much logic in cubits - delegate to services
- Cubits coordinate, services execute
