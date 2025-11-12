import 'package:flutter/material.dart';
import '../../../models/event.dart';
import '../../../models/event_type.dart';
import '../../../services/database_service_interface.dart';
import '../../../services/time_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../cubits/schedule_state.dart';
import '../../../widgets/schedule/change_event_time_dialog.dart';
import '../../../widgets/schedule/schedule_next_appointment_dialog.dart';
import '../dialogs/change_event_type_dialog.dart';
import '../../event_detail_screen.dart';

/// Service for managing event CRUD operations, context menu interactions,
/// and event-related UI dialogs. Handles creation, editing, deletion,
/// type changes, and drag-and-drop time adjustments.
class EventManagementService {
  /// Database service for event operations
  final IDatabaseService _dbService;

  /// Book ID for creating new events
  final int _bookId;

  /// Currently selected event for context menu
  Event? _selectedEventForMenu;

  /// Position of context menu
  Offset? _menuPosition;

  /// Callback to update menu state
  final void Function(Event? selectedEvent, Offset? position) onMenuStateChanged;

  /// Callback to navigate to event detail screen
  final Future<bool?> Function(Widget screen) onNavigate;

  /// Callback to reload events from cubit
  final void Function() onReloadEvents;

  /// Callback to update event in cubit
  final void Function(Event event) onUpdateEvent;

  /// Callback to delete event via cubit (soft delete with reason)
  final Future<void> Function(int eventId, String reason) onDeleteEvent;

  /// Callback to hard delete event via cubit (permanent deletion)
  final Future<void> Function(int eventId) onHardDeleteEvent;

  /// Callback to change event time via cubit
  final Future<void> Function(Event event, DateTime startTime, DateTime? endTime, String reason) onChangeEventTime;

  /// Callback to show snackbar
  final void Function(String message, {Color? backgroundColor, int? durationSeconds}) onShowSnackbar;

  /// Callback to check if widget is mounted
  final bool Function() isMounted;

  /// Callback to get localized string
  final String Function(String Function(AppLocalizations) getter) getLocalizedString;

  /// Callback to sync event to server
  final Future<void> Function(Event event) onSyncEvent;

  /// Callback to set pending next appointment data
  final void Function(PendingNextAppointment) onSetPendingNextAppointment;

  /// Callback to change date
  final Future<void> Function(DateTime) onChangeDate;

  EventManagementService({
    required IDatabaseService dbService,
    required int bookId,
    required this.onMenuStateChanged,
    required this.onNavigate,
    required this.onReloadEvents,
    required this.onUpdateEvent,
    required this.onDeleteEvent,
    required this.onHardDeleteEvent,
    required this.onChangeEventTime,
    required this.onShowSnackbar,
    required this.isMounted,
    required this.getLocalizedString,
    required this.onSyncEvent,
    required this.onSetPendingNextAppointment,
    required this.onChangeDate,
  })  : _dbService = dbService,
        _bookId = bookId;

  /// Get currently selected event for menu
  Event? get selectedEventForMenu => _selectedEventForMenu;

  /// Get menu position
  Offset? get menuPosition => _menuPosition;

  /// Create a new event and navigate to detail screen
  Future<void> createEvent({
    DateTime? startTime,
    String? name,
    String? recordNumber,
    EventType? eventType,
  }) async {
    final now = TimeService.instance.now();
    final defaultStartTime = startTime ??
        DateTime(now.year, now.month, now.day, now.hour, (now.minute ~/ 15) * 15);

    final newEvent = Event(
      bookId: _bookId,
      name: name ?? '',
      recordNumber: recordNumber ?? '',
      eventType: eventType ?? EventType.consultation, // Default to consultation for new events
      startTime: defaultStartTime,
      createdAt: now,
      updatedAt: now,
    );

    final result = await onNavigate(
      EventDetailScreen(
        event: newEvent,
        isNew: true,
      ),
    );

    if (result == true) {
      onReloadEvents();
    }
  }

  /// Edit an existing event
  Future<void> editEvent(Event event) async {
    final result = await onNavigate(
      EventDetailScreen(
        event: event,
        isNew: false,
      ),
    );

    if (result == true) {
      onReloadEvents();
    }
  }

  /// Schedule next appointment from existing event
  Future<void> scheduleNextAppointment(Event originalEvent, BuildContext context) async {
    // Show dialog to get days and event type
    final result = await showScheduleNextAppointmentDialog(context, originalEvent);
    if (result == null) return; // User cancelled

    // Calculate target date
    final targetDate = originalEvent.startTime.add(Duration(days: result.daysFromOriginal));

    // Store pending appointment data
    onSetPendingNextAppointment(
      PendingNextAppointment(
        name: originalEvent.name,
        recordNumber: originalEvent.recordNumber ?? '',
        eventType: result.eventType,
      ),
    );

    // Navigate to target date
    await onChangeDate(targetDate);

    // Close menu
    closeEventMenu();
  }

  /// Show context menu for event
  void showEventContextMenu(Event event, Offset position) {
    _selectedEventForMenu = event;
    _menuPosition = position;
    onMenuStateChanged(_selectedEventForMenu, _menuPosition);
  }

  /// Close context menu
  void closeEventMenu() {
    _selectedEventForMenu = null;
    _menuPosition = null;
    onMenuStateChanged(_selectedEventForMenu, _menuPosition);
  }

  /// Toggle event checked status
  Future<void> toggleEventChecked(Event event, bool isChecked) async {
    try {
      final updatedEvent = event.copyWith(
        isChecked: isChecked,
        updatedAt: TimeService.instance.now(),
      );

      await _dbService.updateEvent(updatedEvent);
      onUpdateEvent(updatedEvent);

      // Sync to server in background (best effort)
      onSyncEvent(updatedEvent);
    } catch (e) {
      if (isMounted()) {
        onShowSnackbar(
          getLocalizedString((l10n) => l10n.errorUpdatingEvent(e.toString())),
        );
      }
    }
  }

  /// Handle menu action
  Future<void> handleMenuAction(String action, Event event, BuildContext context) async {
    if (action == 'changeType') {
      await changeEventType(event, context);
      closeEventMenu();
    } else if (action == 'changeTime') {
      await changeEventTimeFromSchedule(event, context);
      closeEventMenu();
    } else if (action == 'remove') {
      await removeEventFromSchedule(event, context);
      closeEventMenu();
    } else if (action == 'delete') {
      await deleteEventFromSchedule(event, context);
      closeEventMenu();
    }
  }

  /// Change event type
  Future<void> changeEventType(Event event, BuildContext context) async {
    final eventTypes = [
      EventType.consultation,
      EventType.surgery,
      EventType.followUp,
      EventType.emergency,
      EventType.checkUp,
      EventType.treatment,
    ];

    final selectedType = await showChangeEventTypeDialog(
      context,
      event,
      eventTypes,
      getLocalizedEventType,
    );

    if (selectedType != null && selectedType != event.eventType) {
      try {
        final updatedEvent = event.copyWith(
          eventType: selectedType,
          updatedAt: TimeService.instance.now(),
        );

        await _dbService.updateEvent(updatedEvent);
        onUpdateEvent(updatedEvent);

        if (isMounted()) {
          onShowSnackbar(
            getLocalizedString((l10n) => l10n.eventTypeChanged),
          );
        }
      } catch (e) {
        if (isMounted()) {
          onShowSnackbar(
            getLocalizedString((l10n) => l10n.errorUpdatingEvent(e.toString())),
          );
        }
      }
    }
  }

  /// Change event time from schedule view
  Future<void> changeEventTimeFromSchedule(Event event, BuildContext context) async {
    final result = await showChangeEventTimeDialog(context, event);
    if (result == null) return;

    try {
      await onChangeEventTime(
        event,
        result.startTime,
        result.endTime,
        result.reason,
      );

      if (isMounted()) {
        onShowSnackbar(
          getLocalizedString((l10n) => l10n.eventTimeChangedSuccess),
          backgroundColor: Colors.green,
          durationSeconds: 2,
        );
      }
    } catch (e) {
      if (isMounted()) {
        onShowSnackbar(
          getLocalizedString((l10n) => l10n.errorChangingEventTime(e.toString())),
          backgroundColor: Colors.red,
          durationSeconds: 3,
        );
      }
    }
  }

  /// Remove event from schedule (soft delete with reason)
  Future<void> removeEventFromSchedule(Event event, BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;

    // Show reason dialog
    final reason = await showDialog<String>(
      context: context,
      builder: (context) {
        final reasonController = TextEditingController();
        return AlertDialog(
          title: Text(l10n.removeEvent),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.removeEventDescription),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                decoration: InputDecoration(
                  labelText: l10n.reasonForRemovalLabel,
                  hintText: l10n.enterReasonHint,
                ),
                autofocus: true,
                maxLines: 2,
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
                if (reasonController.text.trim().isNotEmpty) {
                  Navigator.pop(context, reasonController.text.trim());
                }
              },
              style: TextButton.styleFrom(foregroundColor: Colors.orange),
              child: Text(l10n.ok),
            ),
          ],
        );
      },
    );

    if (reason != null && reason.isNotEmpty) {
      try {
        await onDeleteEvent(event.id!, reason);

        if (isMounted()) {
          onShowSnackbar(
            getLocalizedString((l10n) => l10n.eventRemovedSuccessfully),
          );
        }
      } catch (e) {
        if (isMounted()) {
          onShowSnackbar(
            getLocalizedString((l10n) => l10n.errorRemovingEventMessage(e.toString())),
          );
        }
      }
    }
  }

  /// Delete event from schedule (permanent deletion)
  Future<void> deleteEventFromSchedule(Event event, BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteEvent),
        content: Text(l10n.confirmDeleteEvent(event.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await onHardDeleteEvent(event.id!);

        if (isMounted()) {
          onShowSnackbar(
            getLocalizedString((l10n) => l10n.eventDeleted),
          );
        }
      } catch (e) {
        if (isMounted()) {
          onShowSnackbar(
            getLocalizedString((l10n) => l10n.errorDeletingEvent(e.toString())),
          );
        }
      }
    }
  }

  /// Handle event drop (drag-and-drop time change)
  Future<void> handleEventDrop(Event event, DateTime newStartTime, BuildContext context) async {
    // Check if time actually changed
    if (event.startTime.year == newStartTime.year &&
        event.startTime.month == newStartTime.month &&
        event.startTime.day == newStartTime.day &&
        event.startTime.hour == newStartTime.hour &&
        event.startTime.minute == newStartTime.minute) {
      closeEventMenu();
      return;
    }

    final l10n = AppLocalizations.of(context)!;

    // Show reason dialog
    final reason = await showDialog<String>(
      context: context,
      builder: (context) {
        final reasonController = TextEditingController(text: l10n.timeChangedViaDrag);
        return AlertDialog(
          title: Text(l10n.changeEventType),
          content: TextField(
            controller: reasonController,
            decoration: InputDecoration(
              labelText: l10n.reasonForTimeChangeLabel,
              hintText: l10n.enterReasonHint,
            ),
            autofocus: true,
            maxLines: 2,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () {
                if (reasonController.text.trim().isNotEmpty) {
                  Navigator.pop(context, reasonController.text.trim());
                }
              },
              child: Text(l10n.ok),
            ),
          ],
        );
      },
    );

    if (reason != null && reason.isNotEmpty) {
      try {
        // Calculate new end time if original event had one
        DateTime? newEndTime;
        if (event.endTime != null) {
          final duration = event.endTime!.difference(event.startTime);
          newEndTime = newStartTime.add(duration);
        }

        final newEvent = await _dbService.changeEventTime(event, newStartTime, newEndTime, reason);
        closeEventMenu();

        onReloadEvents();

        // Sync to server in background (best effort, no error handling needed)
        onSyncEvent(newEvent);

        if (isMounted()) {
          onShowSnackbar(
            getLocalizedString((l10n) => l10n.eventTimeChangedSuccessfully),
          );
        }
      } catch (e) {
        if (isMounted()) {
          onShowSnackbar(
            getLocalizedString((l10n) => l10n.errorChangingTime(e.toString())),
          );
        }
      }
    } else {
      closeEventMenu();
    }
  }

  /// Get localized string for EventType
  String getLocalizedEventType(BuildContext context, EventType type) {
    final l10n = AppLocalizations.of(context)!;
    switch (type) {
      case EventType.consultation:
        return l10n.consultation;
      case EventType.surgery:
        return l10n.surgery;
      case EventType.followUp:
        return l10n.followUp;
      case EventType.emergency:
        return l10n.emergency;
      case EventType.checkUp:
        return l10n.checkUp;
      case EventType.treatment:
        return l10n.treatment;
      case EventType.other:
        return 'Other'; // Default for unspecified types
    }
  }

  /// Get color for event type
  Color getEventTypeColor(EventType eventType) {
    // Color coding based on event type enum (type-safe)
    final Color baseColor;

    switch (eventType) {
      case EventType.consultation:
        baseColor = Colors.blue;
        break;
      case EventType.surgery:
        baseColor = Colors.red;
        break;
      case EventType.followUp:
        baseColor = Colors.green;
        break;
      case EventType.emergency:
        baseColor = Colors.orange;
        break;
      case EventType.checkUp:
        baseColor = Colors.purple;
        break;
      case EventType.treatment:
        baseColor = Colors.cyan;
        break;
      case EventType.other:
        // Default color for unknown types
        baseColor = Colors.grey;
        break;
    }

    // Reduce saturation to 60%
    final hslColor = HSLColor.fromColor(baseColor);
    return hslColor.withSaturation(0.60).toColor();
  }
}
