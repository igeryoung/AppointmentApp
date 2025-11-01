# Phase 3: Service Layer Cleanup

**Duration:** Week 3-4
**Risk Level:** Medium
**Dependencies:** Phase 2 complete

## Objective

Split ContentService (770 lines) into focused services, each handling a specific domain. Improve separation between API communication, caching, and synchronization concerns.

## Checklist

### Create NoteContentService

- [ ] Create `lib/services/note_content_service.dart`
- [ ] Move note-related methods from ContentService
- [ ] Methods: `getNote()`, `saveNote()`, `deleteNote()`, `preloadNotes()`, `syncNote()`
- [ ] Use NoteRepository and ApiClient internally
- [ ] Handle cache-first logic
- [ ] Handle dirty flag management
- [ ] Target: <250 lines

### Create DrawingContentService

- [ ] Create `lib/services/drawing_content_service.dart`
- [ ] Move drawing-related methods from ContentService
- [ ] Methods: `getDrawing()`, `saveDrawing()`, `deleteDrawing()`, `preloadDrawings()`
- [ ] Use DrawingRepository and ApiClient internally
- [ ] Handle save queue for race condition prevention
- [ ] Handle cache-first logic
- [ ] Target: <250 lines

### Create SyncCoordinator

- [ ] Create `lib/services/sync_coordinator.dart`
- [ ] Move bulk sync methods from ContentService
- [ ] Methods: `syncAllDirtyNotes()`, `syncDirtyNotesForBook()`, `syncAllDirtyDrawings()`, `hasPendingChanges()`
- [ ] Coordinate between NoteContentService and DrawingContentService
- [ ] Handle conflict resolution
- [ ] Handle batch operations
- [ ] Handle sync errors and retries
- [ ] Target: <200 lines

### Refactor CacheManager

- [ ] Update `lib/services/cache_manager.dart`
- [ ] Remove duplicated logic now in repositories
- [ ] Focus on high-level cache coordination
- [ ] Work with CachePolicyManager from Phase 2
- [ ] Methods: `getCacheStatus()`, `clearCacheForBook()`, `getCacheStatistics()`
- [ ] Target: <150 lines

### Update ApiClient

- [ ] Review `lib/services/api_client.dart`
- [ ] Ensure consistent error handling
- [ ] Add timeout configurations
- [ ] Add retry logic for transient failures
- [ ] Keep existing functionality intact

### Update Service Locator

- [ ] Register NoteContentService
- [ ] Register DrawingContentService
- [ ] Register SyncCoordinator
- [ ] Update CacheManager registration
- [ ] Define dependency chain correctly

### Deprecate Old ContentService

- [ ] Mark ContentService as @deprecated
- [ ] Add migration guide in comments
- [ ] Keep for backward compatibility temporarily
- [ ] Delegate to new services internally

## Testing

### Unit Tests Required

**File:** `test/services/note_content_service_test.dart`
- Get note (cache hit)
- Get note (cache miss, fetch from API)
- Get note (offline, cache only)
- Save note (online, syncs immediately)
- Save note (offline, marks dirty)
- Delete note (removes from cache and server)
- Preload notes (batches efficiently)
- Sync note (updates server, marks clean)

**File:** `test/services/drawing_content_service_test.dart`
- Get drawing (cache hit)
- Get drawing (cache miss, fetch from API)
- Save drawing (handles queue correctly)
- Save drawing (prevents race conditions)
- Preload drawings (batches efficiently)

**File:** `test/services/sync_coordinator_test.dart`
- Sync all dirty notes
- Sync notes for specific book
- Handle sync failures gracefully
- Report sync progress
- Handle conflicts (optimistic locking)
- Batch operations efficiently

**File:** `test/services/cache_manager_test.dart`
- Get cache status
- Clear cache for book
- Get cache statistics
- Cache policy enforcement

### Integration Tests Required

**File:** `test/integration/service_layer_integration_test.dart`
- Save note → goes to cache → syncs to server
- Offline: Save note → stays dirty → online → syncs automatically
- Conflict: Two devices edit same note → conflict resolution works
- Bulk sync: Multiple dirty notes → all sync correctly

### Regression Testing

- [ ] Run all characterization tests from Phase 1
- [ ] Run all repository tests from Phase 2
- [ ] All tests still pass

## Definition of Done

- [ ] NoteContentService created (<250 lines)
- [ ] DrawingContentService created (<250 lines)
- [ ] SyncCoordinator created (<200 lines)
- [ ] CacheManager refactored (<150 lines)
- [ ] All services registered in service locator
- [ ] Old ContentService deprecated
- [ ] All unit tests passing
- [ ] Integration tests passing
- [ ] No behavior changes
- [ ] App still works with deprecated ContentService

## Rollback Plan

If issues arise:
1. Remove @deprecated from ContentService
2. Continue using ContentService directly
3. Keep new services but don't expose them yet
4. Debug and fix issues offline
5. Re-attempt when ready

## Notes

- Cache-first strategy is critical - must be preserved
- Drawing save queue prevents race conditions - don't break it
- Sync logic is complex - test thoroughly
- Network error handling must be robust
- Offline experience is a core feature - protect it
