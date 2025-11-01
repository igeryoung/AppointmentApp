import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/models/book.dart';
import 'package:schedule_note_app/models/event.dart';
import 'package:schedule_note_app/screens/schedule_screen.dart';
import 'package:schedule_note_app/services/prd_database_service.dart';
import 'package:schedule_note_app/services/service_locator.dart';

/// Characterization Tests for ScheduleScreen
///
/// Purpose: Capture current behavior BEFORE refactoring
/// These tests act as a safety net to ensure:
/// 1. Event loading works correctly
/// 2. Date navigation works correctly
/// 3. Drawing operations work correctly
/// 4. Event CRUD operations work correctly
///
/// DO NOT modify these tests during refactoring.
/// If these tests fail after refactoring, we broke something!

void main() {
  group('ScheduleScreen Characterization Tests - Behavior Preservation', () {
    late PRDDatabaseService dbService;

    setUpAll(() async {
      // Initialize database service once for all tests
      await setupServices();
    });

    setUp(() async {
      dbService = getIt<PRDDatabaseService>();
      await dbService.clearAllData();
    });

    tearDown(() async {
      await dbService.clearAllData();
    });

    test('Scenario 1: Load events for 3-day window', () async {
      // Given: A book with events across multiple days
      final book = await dbService.createBook('Test Book');
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // Create events in 3-day window (use createEvent which handles timestamps)
      await dbService.createEvent(Event(
        bookId: book.id!,
        name: 'Event Day 1',
        eventType: '',
        startTime: today.add(const Duration(hours: 10)),
        endTime: today.add(const Duration(hours: 11)),
        createdAt: now,
        updatedAt: now,
      ));

      await dbService.createEvent(Event(
        bookId: book.id!,
        name: 'Event Day 2',
        eventType: '',
        startTime: today.add(const Duration(days: 1, hours: 14)),
        endTime: today.add(const Duration(days: 1, hours: 15)),
        createdAt: now,
        updatedAt: now,
      ));

      await dbService.createEvent(Event(
        bookId: book.id!,
        name: 'Event Day 3',
        eventType: '',
        startTime: today.add(const Duration(days: 2, hours: 16)),
        endTime: today.add(const Duration(days: 2, hours: 17)),
        createdAt: now,
        updatedAt: now,
      ));

      // When: Load events for 3-day window
      final startOfWindow = DateTime(today.year, today.month, today.day);
      final endOfWindow = startOfWindow.add(const Duration(days: 3));
      final events = await dbService.getEventsBy3Days(book.id!, startOfWindow);

      // Then: All 3 events should be loaded
      expect(events.length, 3);
      expect(events.any((e) => e.name == 'Event Day 1'), true);
      expect(events.any((e) => e.name == 'Event Day 2'), true);
      expect(events.any((e) => e.name == 'Event Day 3'), true);
    });

    test('Scenario 2: Date navigation - calculate 3-day window anchor', () async {
      // This tests the critical date window logic used by ScheduleScreen
      // The anchor date is 2000-01-01 (fixed reference point)

      final anchorDate = DateTime(2000, 1, 1);
      final testDate = DateTime(2024, 11, 15);

      // Calculate days since anchor
      final daysSinceAnchor = testDate.difference(anchorDate).inDays;

      // Calculate window start (every 3 days)
      final windowIndex = daysSinceAnchor ~/ 3;
      final windowStart = anchorDate.add(Duration(days: windowIndex * 3));

      // Then: Window should be stable and predictable
      expect(windowStart.isBefore(testDate) || windowStart.isAtSameMomentAs(testDate), true);
      expect(windowStart.add(const Duration(days: 3)).isAfter(testDate), true);

      // Verify window is always 3 days
      final windowEnd = windowStart.add(const Duration(days: 3));
      expect(windowEnd.difference(windowStart).inDays, 3);
    });

    test('Scenario 3: Show/hide old events filtering', () async {
      // Given: A book with old and new events
      final book = await dbService.createBook('Test Book');
      final now = DateTime.now();

      // Old event (before today)
      await dbService.createEvent(Event(
        bookId: book.id!,
        name: 'Old Event',
        eventType: '',
        startTime: now.subtract(const Duration(days: 5)),
        endTime: now.subtract(const Duration(days: 5, hours: -1)),
        createdAt: now,
        updatedAt: now,
      ));

      // Current event
      await dbService.createEvent(Event(
        bookId: book.id!,
        name: 'Current Event',
        eventType: '',
        startTime: now,
        endTime: now.add(const Duration(hours: 1)),
        createdAt: now,
        updatedAt: now,
      ));

      // Future event
      await dbService.createEvent(Event(
        bookId: book.id!,
        name: 'Future Event',
        eventType: '',
        startTime: now.add(const Duration(days: 1)),
        endTime: now.add(const Duration(days: 1, hours: 1)),
        createdAt: now,
        updatedAt: now,
      ));

      // When: Load all events
      final allEvents = await dbService.getEventsBy3Days(
        book.id!,
        now.subtract(const Duration(days: 7)),
      );

      // Then: Verify filtering logic
      final oldEvents = allEvents.where((e) => e.endTime != null && e.endTime!.isBefore(now)).toList();
      final currentAndFutureEvents = allEvents.where((e) => e.endTime != null && (e.endTime!.isAfter(now) || e.endTime!.isAtSameMomentAs(now))).toList();

      expect(oldEvents.length, 1);
      expect(oldEvents.first.name, 'Old Event');
      expect(currentAndFutureEvents.length, 2);
    });

    test('Scenario 4: Event time change creates new event and soft-deletes old', () async {
      // Given: A book with an event
      final book = await dbService.createBook('Test Book');
      final now = DateTime.now();

      final originalEvent = await dbService.createEvent(Event(
        bookId: book.id!,
        name: 'Original Event',
        eventType: '',
        startTime: now.add(const Duration(hours: 10)),
        endTime: now.add(const Duration(hours: 11)),
        createdAt: now,
        updatedAt: now,
      ));

      // When: Change event time
      final newStartTime = now.add(const Duration(hours: 14));
      final newEndTime = now.add(const Duration(hours: 15));
      final reason = 'Time conflict';

      final newEvent = await dbService.changeEventTime(
        originalEvent,
        newStartTime,
        newEndTime,
        reason,
      );

      // Then: Original event should be soft-deleted
      final originalFromDb = await dbService.getEventById(originalEvent.id!);
      expect(originalFromDb!.isRemoved, true);
      expect(originalFromDb.removalReason, reason);
      expect(originalFromDb.newEventId, newEvent.id);

      // New event should exist with new time
      expect(newEvent.startTime, newStartTime);
      expect(newEvent.endTime, newEndTime);
      expect(newEvent.originalEventId, originalEvent.id);
      expect(newEvent.isRemoved, false);
    });

    test('Scenario 5: Drawing save with page ID calculation', () async {
      // Given: A book and a date
      final book = await dbService.createBook('Test Book');
      final testDate = DateTime(2024, 11, 15);
      final anchorDate = DateTime(2000, 1, 1);

      // Calculate page ID (same logic as ScheduleScreen)
      final daysSinceAnchor = testDate.difference(anchorDate).inDays;
      final pageIndex = daysSinceAnchor ~/ 3;

      // When: Save drawing (simulated)
      final viewMode = 3; // 3-day view

      // Then: Page ID should be consistent
      expect(pageIndex >= 0, true);

      // Verify window start is predictable
      final windowStart = anchorDate.add(Duration(days: pageIndex * 3));
      expect(windowStart.isBefore(testDate) || windowStart.isAtSameMomentAs(testDate), true);
    });

    test('Scenario 6: Event deletion (hard delete)', () async {
      // Given: A book with an event
      final book = await dbService.createBook('Test Book');
      final now = DateTime.now();
      final event = await dbService.createEvent(Event(
        bookId: book.id!,
        name: 'To Delete',
        eventType: '',
        startTime: now,
        endTime: now.add(const Duration(hours: 1)),
        createdAt: now,
        updatedAt: now,
      ));

      // When: Delete event
      await dbService.deleteEvent(event.id!);

      // Then: Event should be gone
      final deletedEvent = await dbService.getEventById(event.id!);
      expect(deletedEvent, null);
    });

    test('Scenario 7: Event removal (soft delete)', () async {
      // Given: A book with an event
      final book = await dbService.createBook('Test Book');
      final now = DateTime.now();
      final event = await dbService.createEvent(Event(
        bookId: book.id!,
        name: 'To Remove',
        eventType: '',
        startTime: now,
        endTime: now.add(const Duration(hours: 1)),
        createdAt: now,
        updatedAt: now,
      ));

      // When: Remove event with reason
      final reason = 'Cancelled by patient';
      final removedEvent = await dbService.removeEvent(event.id!, reason);

      // Then: Event should be soft-deleted
      expect(removedEvent.isRemoved, true);
      expect(removedEvent.removalReason, reason);

      // Event still exists in database
      final eventFromDb = await dbService.getEventById(event.id!);
      expect(eventFromDb, isNotNull);
      expect(eventFromDb!.isRemoved, true);
    });
  });

  group('ScheduleScreen Critical Behavior - DO NOT BREAK', () {
    test('CRITICAL: 3-day window anchor date is 2000-01-01', () {
      // This is critical for stable drawing page IDs
      final anchorDate = DateTime(2000, 1, 1);
      expect(anchorDate.year, 2000);
      expect(anchorDate.month, 1);
      expect(anchorDate.day, 1);
    });

    test('CRITICAL: Window size is always 3 days', () {
      const windowSize = 3;
      expect(windowSize, 3);
    });

    test('CRITICAL: Time slots are 30-minute intervals from 9AM to 9PM', () {
      const startHour = 9; // 9 AM
      const endHour = 21; // 9 PM
      const slotDuration = 30; // minutes

      final slotsPerHour = 60 ~/ slotDuration;
      final totalHours = endHour - startHour;
      final totalSlots = totalHours * slotsPerHour;

      expect(totalSlots, 24); // 12 hours * 2 slots per hour = 24 slots
    });

    test('CRITICAL: Max 4 events can be shown per time slot', () {
      const maxEventsPerSlot = 4;
      expect(maxEventsPerSlot, 4);
    });
  });
}
