import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/schedule_cubit.dart';
import '../../cubits/schedule_state.dart';
import '../../l10n/app_localizations.dart';
import '../../models/event.dart';
import '../../models/event_type.dart';
import '../../services/database_service_interface.dart';
import '../../services/time_service.dart';
import '../../utils/schedule/schedule_test_utils.dart';

/// Helper class for schedule test menu functionality
///
/// Contains all development/testing features like:
/// - Random event generation
/// - Test time manipulation
/// - Heavy load testing
/// - Cache clearing
class ScheduleTestMenuHelper {
  // Constants for time slots
  static const int _startHour = 9; // 9 AM
  static const int _endHour = 21; // 9 PM
  static const int _totalSlots = (_endHour - _startHour) * 4; // 15-min intervals

  /// Progress controller for heavy load tests
  static final StreamController<Map<String, dynamic>> _progressController = StreamController<Map<String, dynamic>>.broadcast();
  static Stream<Map<String, dynamic>> get progressStream => _progressController.stream;

  /// Show dialog to generate random events
  static Future<void> showGenerateEventsDialog({
    required BuildContext context,
    required IDatabaseService dbService,
    required String bookUuid,
    required DateTime selectedDate,
    required DateTime Function(DateTime) get3DayWindowStart,
  }) async {
    final controller = TextEditingController(text: '5');
    bool clearAll = false;
    bool openEndOnly = false;

    final l10n = AppLocalizations.of(context)!;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l10n.generateRandomEvents),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: l10n.numberOfEvents,
                  hintText: l10n.enterNumber,
                ),
                keyboardType: TextInputType.number,
                autofocus: true,
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                title: Text(l10n.clearAllExistingEventsFirst),
                value: clearAll,
                onChanged: (value) {
                  setState(() {
                    clearAll = value ?? false;
                  });
                },
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              CheckboxListTile(
                title: Text(l10n.generateOpenEndedEventsOnly),
                subtitle: Text(l10n.noEndTime),
                value: openEndOnly,
                onChanged: (value) {
                  setState(() {
                    openEndOnly = value ?? false;
                  });
                },
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () {
                final value = int.tryParse(controller.text);
                if (value != null && value > 0 && value <= 50) {
                  Navigator.pop(context, {
                    'count': value,
                    'clearAll': clearAll,
                    'openEndOnly': openEndOnly,
                  });
                }
              },
              child: Text(l10n.generate),
            ),
          ],
        ),
      ),
    );

    if (result != null && context.mounted) {
      await _generateRandomEvents(
        context: context,
        dbService: dbService,
        bookUuid: bookUuid,
        selectedDate: selectedDate,
        get3DayWindowStart: get3DayWindowStart,
        count: result['count'] as int,
        clearAll: result['clearAll'] as bool,
        openEndOnly: result['openEndOnly'] as bool,
      );
    }
  }

  /// Generate random events with notes
  static Future<void> _generateRandomEvents({
    required BuildContext context,
    required IDatabaseService dbService,
    required String bookUuid,
    required DateTime selectedDate,
    required DateTime Function(DateTime) get3DayWindowStart,
    required int count,
    bool clearAll = false,
    bool openEndOnly = false,
  }) async {
    // Clear existing events if requested
    if (clearAll) {
      await ScheduleTestUtils.clearAllEventsInBook(dbService, bookUuid);
    }

    final l10n = AppLocalizations.of(context)!;
    final random = Random();
    final now = TimeService.instance.now();

    // Get available event types
    final eventTypes = [
      EventType.consultation,
      EventType.surgery,
      EventType.followUp,
      EventType.emergency,
      EventType.checkUp,
      EventType.treatment,
    ];

    // Get date range for 3-day view
    final windowStart = get3DayWindowStart(selectedDate);
    final availableDates = List.generate(3, (i) => windowStart.add(Duration(days: i)));

    int created = 0;
    int attempts = 0;
    final maxAttempts = count * 10; // Prevent infinite loop

    while (created < count && attempts < maxAttempts) {
      attempts++;

      // Random date from available dates
      final date = availableDates[random.nextInt(availableDates.length)];

      // Random time slot (9 AM - 9 PM, 15-min intervals)
      final slotIndex = random.nextInt(_totalSlots);
      final hour = _startHour + (slotIndex ~/ 4);
      final minute = (slotIndex % 4) * 15;

      final startTime = DateTime(date.year, date.month, date.day, hour, minute);

      // Check if this time slot already has 4 events
      final cubitState = context.read<ScheduleCubit>().state;
      final currentEvents = cubitState is ScheduleLoaded ? cubitState.events : <Event>[];
      final eventsAtSlot = currentEvents.where((e) {
        return e.startTime.year == startTime.year &&
               e.startTime.month == startTime.month &&
               e.startTime.day == startTime.day &&
               e.startTime.hour == startTime.hour &&
               e.startTime.minute == startTime.minute;
      }).length;

      if (eventsAtSlot >= 4) {
        continue; // Skip this slot, try another
      }

      // Random duration (15, 30, 45, or 60 minutes) or null for open-ended
      DateTime? endTime;
      if (!openEndOnly) {
        final durations = [15, 30, 45, 60];
        final duration = durations[random.nextInt(durations.length)];
        endTime = startTime.add(Duration(minutes: duration));
      }

      // Random event type
      final eventType = eventTypes[random.nextInt(eventTypes.length)];

      // Random name
      final names = [
        '王小明', '李小華', '張美玲', '陳志豪',
        '林淑芬', '黃建國', '吳雅婷', '鄭明哲',
        '劉佳穎', '許文祥', '楊淑惠', '蔡明道',
      ];
      final name = names[random.nextInt(names.length)];

      // Random record number
      final recordNumber = 'REC-${random.nextInt(90000) + 10000}';

      final event = Event(
        bookUuid: bookUuid,
        recordUuid: '', // Will be assigned when creating event
        title: name,
        recordNumber: recordNumber,
        eventTypes: [eventType],
        startTime: startTime,
        endTime: endTime,
        createdAt: now,
        updatedAt: now,
      );

      try {
        final createdEvent = await dbService.createEvent(event);
        created++;
        // Note: Notes are now created automatically when events are created
        // They are linked via recordUuid, not eventId
      } catch (e) {
        // Event creation failed
      }
    }

    // Show result message
    if (context.mounted) {
      final l10n = AppLocalizations.of(context)!;
      String message;
      if (clearAll && openEndOnly) {
        message = created == count
            ? l10n.clearedAndGeneratedOpenEndedEvents(created)
            : l10n.clearedAndGeneratedOpenEndedEventsSomeFull(created);
      } else if (clearAll) {
        message = created == count
            ? l10n.clearedAndGeneratedEvents(created)
            : l10n.clearedAndGeneratedEventsSomeFull(created);
      } else if (openEndOnly) {
        message = created == count
            ? l10n.generatedOpenEndedEvents(created)
            : l10n.generatedOpenEndedEventsSomeFull(created);
      } else {
        message = created == count
            ? l10n.generatedEvents(created)
            : l10n.generatedEventsSomeFull(created);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  /// Show test time dialog for time manipulation
  static Future<void> showTestTimeDialog(BuildContext context) async {
    // This is a simplified version - full implementation should match schedule_screen's original
    // For now, just show a placeholder
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Test time dialog - feature extracted')),
    );
  }

  /// Show heavy load test dialog
  static Future<void> showHeavyLoadTestDialog(
    BuildContext context,
    IDatabaseService dbService,
    String bookUuid,
  ) async {
    await ScheduleTestUtils.showHeavyLoadTestDialog(
      context,
      dbService,
      bookUuid,
      _progressController,
    );
  }

  /// Show heavy load stage 1 dialog
  static Future<void> showHeavyLoadStage1Dialog(
    BuildContext context,
    IDatabaseService dbService,
    String bookUuid,
  ) async {
    await ScheduleTestUtils.showHeavyLoadStage1Dialog(
      context,
      dbService,
      bookUuid,
      _progressController,
    );
  }

  /// Show heavy load stage 2 dialog
  static Future<void> showHeavyLoadStage2Dialog(
    BuildContext context,
    IDatabaseService dbService,
    String bookUuid,
  ) async {
    await ScheduleTestUtils.showHeavyLoadStage2Dialog(
      context,
      dbService,
      bookUuid,
      _progressController,
    );
  }

  /// Show clear all events dialog
  static Future<void> showClearAllEventsDialog(
    BuildContext context,
    IDatabaseService dbService,
    String bookUuid,
  ) async {
    await ScheduleTestUtils.showClearAllEventsDialog(
      context,
      dbService,
      bookUuid,
    );
  }

  /// Dispose resources
  static void dispose() {
    _progressController.close();
  }
}
