# Phase 1: Foundation & Testing

**Duration:** Week 1-2
**Risk Level:** Low
**Dependencies:** None

## Objective

Set up infrastructure for dependency injection and state management, and establish baseline tests to ensure refactoring doesn't break existing functionality.

## Checklist

### Setup Dependencies

- [ ] Add `get_it: ^7.6.0` to pubspec.yaml
- [ ] Add `flutter_bloc: ^8.1.3` to pubspec.yaml
- [ ] Run `flutter pub get`
- [ ] Verify app still builds and runs

### Create Service Locator

- [ ] Create `lib/services/service_locator.dart`
- [ ] Define `setupServices()` function
- [ ] Register existing services (database, time service, etc.)
- [ ] Initialize in `main()` before `runApp()`

### Create Repository Interfaces

- [ ] Create `lib/repositories/` directory
- [ ] Create `lib/repositories/book_repository.dart` (interface only)
- [ ] Create `lib/repositories/event_repository.dart` (interface only)
- [ ] Create `lib/repositories/note_repository.dart` (interface only)
- [ ] Create `lib/repositories/drawing_repository.dart` (interface only)
- [ ] Define standard CRUD methods for each

### Write Characterization Tests

- [ ] Create `test/characterization/` directory
- [ ] Test: Create and retrieve book
- [ ] Test: Create and retrieve event
- [ ] Test: Save and load note from cache
- [ ] Test: Save and load drawing from cache
- [ ] Test: Database migration (v1 → v9)
- [ ] Test: Device credentials storage
- [ ] Test: Offline cache behavior

## Testing

### Unit Tests Required

**File:** `test/services/service_locator_test.dart`
- Services are registered correctly
- Services are singletons
- Can retrieve registered services

**File:** `test/characterization/database_operations_test.dart`
- All existing database operations work as before
- Data integrity maintained
- Foreign key constraints working

**File:** `test/characterization/cache_behavior_test.dart`
- Cache-first strategy works
- Dirty flag tracking works
- Offline data persists

### Manual Testing

- [ ] Launch app on iOS
- [ ] Launch app on Android
- [ ] Launch app on Web
- [ ] Create a book
- [ ] Create an event
- [ ] Add a note with drawing
- [ ] Go offline and verify data loads from cache
- [ ] Go online and verify sync works

## Definition of Done

- [ ] All dependencies added and app builds
- [ ] Service locator created and initialized
- [ ] All repository interfaces defined
- [ ] Characterization tests written and passing
- [ ] App behavior unchanged from user perspective
- [ ] Manual smoke test passed on all platforms

## Rollback Plan

If issues arise:
1. Remove get_it and flutter_bloc from pubspec.yaml
2. Delete service_locator.dart
3. Delete repositories/ directory
4. Keep characterization tests (still valuable)

## Notes

- Keep this phase simple - only setup, no actual refactoring yet
- Characterization tests are critical - they protect us in later phases
- Repository interfaces are just contracts, no implementation yet
