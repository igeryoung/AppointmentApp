# Phase 6: Cleanup & Standardization

**Duration:** Week 6-7
**Risk Level:** Low
**Dependencies:** Phase 5 complete

## Objective

Remove technical debt, delete unused code, consolidate patterns, and improve code consistency across the codebase.

## Checklist

### Remove Legacy Code

- [ ] Delete `lib/legacy/screens/calendar_screen.dart`
- [ ] Delete `lib/legacy/screens/appointment_detail_screen.dart`
- [ ] Delete `lib/legacy/providers/book_provider.dart`
- [ ] Delete `lib/legacy/providers/appointment_provider.dart`
- [ ] Delete `lib/legacy/services/prd_database_service.dart` (has CRITICAL BUG)
- [ ] Delete `lib/legacy/models/appointment.dart`
- [ ] Delete entire `lib/legacy/` directory
- [ ] Update imports if any stray references exist
- [ ] Expected deletion: ~1,500 lines

### Remove Deprecated Code

- [ ] Remove @deprecated tag from ContentService (if fully replaced)
- [ ] Delete ContentService if no longer used
- [ ] Remove @deprecated tag from PRDDatabaseService methods
- [ ] Keep PRDDatabaseService only if still needed as facade
- [ ] Clean up unused imports

### Consolidate Duplicate Code

- [ ] Identify remaining service initialization patterns
- [ ] Move to service_locator if needed
- [ ] Remove duplicate network monitoring code
- [ ] Consolidate error handling (should use ErrorHandler utility)
- [ ] Standardize loading indicators (use common widget)
- [ ] Standardize empty states (use common widget)

### Standardize Model Serialization

- [ ] Review all models (Book, Event, Note, ScheduleDrawing)
- [ ] Ensure consistent toMap/fromMap patterns
- [ ] Separate API serialization from DB serialization if needed
- [ ] Document serialization conventions
- [ ] Consider creating serializer classes if helpful

### Organize Project Structure

- [ ] Ensure all repositories in `lib/repositories/`
- [ ] Ensure all cubits in `lib/cubits/`
- [ ] Ensure all screens in `lib/screens/{screen_name}/`
- [ ] Ensure all shared widgets in `lib/widgets/common/`
- [ ] Ensure all utilities in `lib/utils/`
- [ ] Create barrel files (index.dart) if helpful

### Update Documentation

- [ ] Update README.md with new architecture
- [ ] Document dependency injection pattern
- [ ] Document BLoC/Cubit usage
- [ ] Document repository pattern
- [ ] Update contribution guidelines if any
- [ ] Add architecture diagram if helpful

### Review Dependencies

- [ ] Run `flutter pub outdated`
- [ ] Update dependencies if safe
- [ ] Remove unused dependencies
- [ ] Document why each dependency is needed

### Code Quality

- [ ] Run `dart analyze` and fix issues
- [ ] Run `flutter analyze` and fix issues
- [ ] Fix linter warnings
- [ ] Ensure consistent code formatting
- [ ] Add missing documentation comments
- [ ] Review TODOs and FIXMEs in code

## Testing

### Regression Testing

- [ ] Run all unit tests
- [ ] Run all integration tests
- [ ] Run all widget tests
- [ ] All tests passing
- [ ] No new warnings

### Manual Testing

- [ ] Full app smoke test on iOS
- [ ] Full app smoke test on Android
- [ ] Full app smoke test on Web
- [ ] Test all major user flows
- [ ] Test offline mode
- [ ] Test sync after coming online

## Definition of Done

- [ ] Legacy directory deleted (~1,500 lines removed)
- [ ] No @deprecated code remaining
- [ ] All duplicate patterns consolidated
- [ ] Project structure organized consistently
- [ ] Documentation updated
- [ ] Dependencies reviewed and cleaned
- [ ] All analyzer issues resolved
- [ ] All tests passing
- [ ] Manual smoke tests passed

## Rollback Plan

Legacy code deletion is easily reversible via git:
1. `git revert <commit-hash>` if issues found
2. Restore legacy directory
3. Investigate dependencies

For other changes:
1. Revert specific commits
2. Fix issues separately
3. Re-apply when ready

## Notes

- This phase should be low-risk - mostly deletions and organization
- Don't rush - take time to review code quality
- Good time to add missing tests
- Good time to improve documentation
- Consider running code coverage reports
- Celebrate - major refactoring is nearly done!
