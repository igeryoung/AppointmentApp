# Phase 2: Database Layer Refactoring

**Duration:** Week 2-3
**Risk Level:** Medium
**Dependencies:** Phase 1 complete

## Objective

Break down PRDDatabaseService (1,400 lines) into focused repository classes, each handling a single domain entity. Keep existing service as a facade for backward compatibility during transition.

## Checklist

### Extract BookRepository

- [ ] Create `lib/repositories/book_repository_impl.dart`
- [ ] Move book CRUD methods from PRDDatabaseService
- [ ] Implement interface from Phase 1
- [ ] Methods: `getAll()`, `getById()`, `create()`, `update()`, `delete()`, `reorder()`
- [ ] Register in service_locator.dart
- [ ] Write unit tests

### Extract EventRepository

- [ ] Create `lib/repositories/event_repository_impl.dart`
- [ ] Move event CRUD methods from PRDDatabaseService
- [ ] Implement interface from Phase 1
- [ ] Methods: `getAll()`, `getById()`, `getByBookId()`, `getByDateRange()`, `create()`, `update()`, `delete()`
- [ ] Handle event-book foreign key relationship
- [ ] Register in service_locator.dart
- [ ] Write unit tests

### Extract NoteRepository

- [ ] Create `lib/repositories/note_repository_impl.dart`
- [ ] Move note cache methods from PRDDatabaseService
- [ ] Implement interface from Phase 1
- [ ] Methods: `getCached()`, `saveToCache()`, `deleteCache()`, `getDirtyNotes()`, `markClean()`, `getAllCached()`
- [ ] Handle dirty flag tracking
- [ ] Register in service_locator.dart
- [ ] Write unit tests

### Extract DrawingRepository

- [ ] Create `lib/repositories/drawing_repository_impl.dart`
- [ ] Move drawing cache methods from PRDDatabaseService
- [ ] Implement interface from Phase 1
- [ ] Methods: `getCached()`, `saveToCache()`, `deleteCache()`, `getDirtyDrawings()`, `markClean()`
- [ ] Handle dirty flag tracking
- [ ] Register in service_locator.dart
- [ ] Write unit tests

### Extract Supporting Classes

- [ ] Create `lib/database/database_migrations.dart`
- [ ] Move all migration logic (v1-v9) from PRDDatabaseService
- [ ] Create `lib/services/cache_policy_manager.dart`
- [ ] Move cache management logic from PRDDatabaseService
- [ ] Methods: `shouldCache()`, `getCacheStats()`, `cleanupOldCache()`, `clearAllCache()`

### Extract DeviceRepository

- [ ] Create `lib/repositories/device_repository_impl.dart`
- [ ] Move device credential methods from PRDDatabaseService
- [ ] Methods: `getDeviceId()`, `saveDeviceId()`, `getDeviceToken()`, `saveDeviceToken()`
- [ ] Register in service_locator.dart

### Update PRDDatabaseService

- [ ] Keep PRDDatabaseService as facade
- [ ] Delegate all calls to appropriate repositories
- [ ] Mark methods as @deprecated with migration notes
- [ ] Keep initialization and connection management
- [ ] PRDDatabaseService should be <300 lines now

### Update WebPRDDatabaseService

- [ ] Apply same repository pattern for web implementation
- [ ] Ensure consistency with mobile implementation

## Testing

### Unit Tests Required

**File:** `test/repositories/book_repository_test.dart`
- Create book
- Get book by ID
- Get all books
- Update book
- Delete book
- Reorder books

**File:** `test/repositories/event_repository_test.dart`
- Create event
- Get event by ID
- Get events by book ID
- Get events by date range
- Update event
- Delete event
- Cascade delete when book deleted

**File:** `test/repositories/note_repository_test.dart`
- Save note to cache
- Retrieve cached note
- Delete cached note
- Get dirty notes
- Mark note as clean
- Dirty flag persists correctly

**File:** `test/repositories/drawing_repository_test.dart`
- Save drawing to cache
- Retrieve cached drawing
- Delete cached drawing
- Get dirty drawings
- Mark drawing as clean

**File:** `test/database/database_migrations_test.dart`
- Migration from v1 to v9 works
- All tables created correctly
- Foreign keys enforced
- Indexes created

**File:** `test/services/cache_policy_manager_test.dart`
- Cache policy decisions
- Cache cleanup works
- Cache statistics accurate

### Integration Tests Required

**File:** `test/integration/repository_integration_test.dart`
- Create book → create event → save note flow
- Verify foreign key relationships
- Verify data integrity across repositories

### Regression Testing

- [ ] Run all characterization tests from Phase 1
- [ ] All tests still pass
- [ ] No behavior changes

## Definition of Done

- [ ] BookRepository created and tested
- [ ] EventRepository created and tested
- [ ] NoteRepository created and tested
- [ ] DrawingRepository created and tested
- [ ] DeviceRepository created and tested
- [ ] DatabaseMigrations extracted and tested
- [ ] CachePolicyManager extracted and tested
- [ ] PRDDatabaseService reduced to <300 lines
- [ ] All repositories registered in service locator
- [ ] All unit tests passing
- [ ] Integration tests passing
- [ ] Characterization tests still passing
- [ ] App behavior unchanged

## Rollback Plan

If critical issues arise:
1. Revert PRDDatabaseService to original implementation
2. Keep repository classes but don't use them yet
3. Continue using old PRDDatabaseService directly
4. Debug and fix issues before re-attempting

## Notes

- This is the most critical phase - take time to get it right
- Each repository should be <200 lines
- Keep transaction handling consistent with original implementation
- Don't change database schema or queries
- Focus on code organization, not optimization
