import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/schedule_cubit.dart';
import '../../l10n/app_localizations.dart';
import '../../repositories/event_repository.dart';
import '../../services/service_locator.dart';
import '../../services/time_service.dart';
import 'query_appointments_dialog.dart';
import 'test_menu.dart';

/// Helper class for building schedule screen FAB menu
class ScheduleFabMenuHelper {
  static const double fabButtonSize = 56;
  static const double fabSpacing = 12;
  static const double fabMargin = 16;

  /// Menu width in logical pixels.
  static double menuWidth() => fabButtonSize;

  /// Menu height based on current visibility/state.
  static double menuHeight({
    required bool isMenuVisible,
    required bool showGoToToday,
  }) {
    if (!isMenuVisible) return fabButtonSize;
    final buttonCount = 5 + (showGoToToday ? 1 : 0);
    return (buttonCount * fabButtonSize) + ((buttonCount - 1) * fabSpacing);
  }

  /// Build FAB menu widget
  static Widget buildFabMenu({
    required BuildContext context,
    required bool isMenuVisible,
    required VoidCallback onToggleMenu,
    required bool isDrawingMode,
    required bool Function() isViewingToday,
    required DateTime selectedDate,
    required Future<void> Function() saveDrawing,
    required Future<void> Function() loadDrawing,
    required VoidCallback toggleDrawingMode,
    required VoidCallback createEvent,
    required String bookUuid,
    required Function(DateTime) onDateChange,
  }) {
    if (!isMenuVisible) {
      return FloatingActionButton(
        heroTag: 'toggle_fab_menu',
        onPressed: onToggleMenu,
        backgroundColor: Colors.grey.shade600,
        child: const Icon(Icons.menu),
        tooltip: 'Show menu',
      );
    }

    final l10n = AppLocalizations.of(context)!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Test Time FAB (for testing time change behavior)
        FloatingActionButton(
          heroTag: 'test_time',
          onPressed: () => ScheduleTestMenuHelper.showTestTimeDialog(context),
          backgroundColor: TimeService.instance.isTestMode
              ? Colors.red
              : Colors.grey.shade700,
          child: Icon(
            TimeService.instance.isTestMode
                ? Icons.schedule
                : Icons.access_time,
          ),
          tooltip: TimeService.instance.isTestMode
              ? l10n.resetToRealTime
              : l10n.testTimeActive,
        ),
        const SizedBox(height: 12),
        // Go to Today FAB (only show when not viewing today)
        if (!isViewingToday())
          FloatingActionButton(
            heroTag: 'goto_today',
            onPressed: () async {
              if (isDrawingMode) await saveDrawing();
              onDateChange(TimeService.instance.now());
              context.read<ScheduleCubit>().selectDate(selectedDate);
              await loadDrawing();
            },
            backgroundColor: Colors.green,
            child: const Icon(Icons.today),
            tooltip: l10n.goToTodayTooltip,
          ),
        if (!isViewingToday()) const SizedBox(height: 12),
        // Query Appointments FAB (disabled in drawing mode)
        FloatingActionButton(
          heroTag: 'query_appointments',
          onPressed: isDrawingMode
              ? null
              : () => showQueryAppointmentsDialog(
                  context,
                  bookUuid,
                  getIt<IEventRepository>(),
                ),
          backgroundColor: isDrawingMode ? Colors.grey : Colors.teal,
          child: const Icon(Icons.search),
          tooltip: isDrawingMode ? null : l10n.queryAppointments,
        ),
        const SizedBox(height: 12),
        // Drawing mode toggle FAB
        FloatingActionButton(
          heroTag: 'drawing_toggle',
          onPressed: toggleDrawingMode,
          backgroundColor: isDrawingMode ? Colors.orange : Colors.blue,
          child: Icon(isDrawingMode ? Icons.draw : Icons.draw_outlined),
          tooltip: isDrawingMode ? 'Exit Drawing Mode' : 'Enter Drawing Mode',
        ),
        const SizedBox(height: 12),
        // Create event FAB (disabled in drawing mode)
        FloatingActionButton(
          heroTag: 'create_event',
          onPressed: isDrawingMode ? null : createEvent,
          backgroundColor: isDrawingMode ? Colors.grey : null,
          child: const Icon(Icons.add),
          tooltip: l10n.createEvent,
        ),
        const SizedBox(height: 12),
        // Toggle FAB to hide menu (kept at bottom to preserve anchor position)
        FloatingActionButton(
          heroTag: 'toggle_fab_menu',
          onPressed: onToggleMenu,
          backgroundColor: Colors.grey.shade600,
          child: const Icon(Icons.close),
          tooltip: 'Hide menu',
        ),
      ],
    );
  }
}
