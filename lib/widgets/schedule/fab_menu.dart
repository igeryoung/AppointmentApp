import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/schedule_cubit.dart';
import '../../l10n/app_localizations.dart';
import '../../repositories/event_repository.dart';
import '../../services/service_locator.dart';
import '../../services/time_service.dart';
import 'query_appointments_dialog.dart';

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
    final buttonCount = 4 + (showGoToToday ? 1 : 0);
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
      final l10n = AppLocalizations.of(context)!;
      return FloatingActionButton(
        heroTag: 'toggle_fab_menu',
        onPressed: onToggleMenu,
        backgroundColor: Colors.grey.shade600,
        tooltip: l10n.showMenu,
        child: const Icon(Icons.menu),
      );
    }

    final l10n = AppLocalizations.of(context)!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Go to Today FAB (only show when not viewing today)
        if (!isViewingToday())
          FloatingActionButton(
            heroTag: 'goto_today',
            onPressed: () async {
              final scheduleCubit = context.read<ScheduleCubit>();
              if (isDrawingMode) await saveDrawing();
              onDateChange(TimeService.instance.now());
              scheduleCubit.selectDate(selectedDate);
              await loadDrawing();
            },
            backgroundColor: Colors.green,
            tooltip: l10n.goToTodayTooltip,
            child: const Icon(Icons.today),
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
          tooltip: isDrawingMode ? null : l10n.queryAppointments,
          child: const Icon(Icons.search),
        ),
        const SizedBox(height: 12),
        // Drawing mode toggle FAB
        FloatingActionButton(
          heroTag: 'drawing_toggle',
          onPressed: toggleDrawingMode,
          backgroundColor: isDrawingMode ? Colors.orange : Colors.blue,
          tooltip: isDrawingMode ? l10n.exitDrawingMode : l10n.enterDrawingMode,
          child: Icon(isDrawingMode ? Icons.draw : Icons.draw_outlined),
        ),
        const SizedBox(height: 12),
        // Create event FAB (disabled in drawing mode)
        FloatingActionButton(
          heroTag: 'create_event',
          onPressed: isDrawingMode ? null : createEvent,
          backgroundColor: isDrawingMode ? Colors.grey : null,
          tooltip: l10n.createEvent,
          child: const Icon(Icons.add),
        ),
        const SizedBox(height: 12),
        // Toggle FAB to hide menu (kept at bottom to preserve anchor position)
        FloatingActionButton(
          heroTag: 'toggle_fab_menu',
          onPressed: onToggleMenu,
          backgroundColor: Colors.grey.shade600,
          tooltip: l10n.hideMenu,
          child: const Icon(Icons.close),
        ),
      ],
    );
  }
}
