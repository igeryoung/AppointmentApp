import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/schedule_cubit.dart';
import '../../cubits/schedule_state.dart';
import '../../l10n/app_localizations.dart';
import '../../models/event.dart';
import '../../repositories/event_repository.dart';
import '../../services/cache_manager.dart';
import '../../services/database_service_interface.dart';
import '../../services/service_locator.dart';
import '../../services/time_service.dart';
import 'query_appointments_dialog.dart';
import 'test_menu.dart';

/// Helper class for building schedule screen FAB menu
class ScheduleFabMenuHelper {
  /// Build FAB menu widget
  static Widget buildFabMenu({
    required BuildContext context,
    required bool isMenuVisible,
    required VoidCallback onToggleMenu,
    required bool isDrawingMode,
    required bool Function() isViewingToday,
    required DateTime selectedDate,
    required DateTime lastActiveDate,
    required Future<void> Function() saveDrawing,
    required Future<void> Function() loadDrawing,
    required VoidCallback toggleDrawingMode,
    required VoidCallback createEvent,
    required IDatabaseService dbService,
    required String bookUuid,
    required DateTime Function(DateTime) get3DayWindowStart,
    required CacheManager? cacheManager,
    required DateTime Function() getEffectiveDate,
    required Function(List<Event>) preloadNotes,
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
        // Toggle FAB to hide menu
        FloatingActionButton(
          heroTag: 'toggle_fab_menu',
          onPressed: onToggleMenu,
          backgroundColor: Colors.grey.shade600,
          child: const Icon(Icons.close),
          tooltip: 'Hide menu',
        ),
        const SizedBox(height: 12),
        // Test Time FAB (for testing time change behavior)
        FloatingActionButton(
          heroTag: 'test_time',
          onPressed: () => ScheduleTestMenuHelper.showTestTimeDialog(context),
          backgroundColor: TimeService.instance.isTestMode ? Colors.red : Colors.grey.shade700,
          child: Icon(
            TimeService.instance.isTestMode ? Icons.schedule : Icons.access_time,
          ),
          tooltip: TimeService.instance.isTestMode ? l10n.resetToRealTime : l10n.testTimeActive,
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
        if (!isViewingToday())
          const SizedBox(height: 12),
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
        // Generate random events FAB (disabled in drawing mode)
        FloatingActionButton(
          heroTag: 'generate_events',
          onPressed: isDrawingMode
              ? null
              : () => ScheduleTestMenuHelper.showGenerateEventsDialog(
                    context: context,
                    dbService: dbService,
                    bookUuid: bookUuid,
                    selectedDate: selectedDate,
                    get3DayWindowStart: get3DayWindowStart,
                  ),
          backgroundColor: isDrawingMode ? Colors.grey : Colors.purple,
          child: const Icon(Icons.science),
          tooltip: isDrawingMode ? null : 'Generate Random Events',
        ),
        const SizedBox(height: 12),
        // Clear all events FAB (disabled in drawing mode)
        FloatingActionButton(
          heroTag: 'clear_all_events',
          onPressed: isDrawingMode
              ? null
              : () => ScheduleTestMenuHelper.showClearAllEventsDialog(
                    context,
                    dbService,
                    bookUuid,
                  ),
          backgroundColor: isDrawingMode ? Colors.grey : Colors.red.shade700,
          child: const Icon(Icons.delete_sweep),
          tooltip: isDrawingMode ? null : '清除所有活動',
        ),
        const SizedBox(height: 12),
        // Heavy load test Stage 1 FAB (disabled in drawing mode)
        FloatingActionButton(
          heroTag: 'heavy_load_stage1',
          onPressed: isDrawingMode
              ? null
              : () => ScheduleTestMenuHelper.showHeavyLoadStage1Dialog(
                    context,
                    dbService,
                    bookUuid,
                  ),
          backgroundColor: isDrawingMode ? Colors.grey : Colors.blue,
          child: const Icon(Icons.create),
          tooltip: isDrawingMode ? null : l10n.heavyLoadStage1Only,
        ),
        const SizedBox(height: 12),
        // Heavy load test Stage 2 FAB (disabled in drawing mode)
        FloatingActionButton(
          heroTag: 'heavy_load_stage2',
          onPressed: isDrawingMode
              ? null
              : () => ScheduleTestMenuHelper.showHeavyLoadStage2Dialog(
                    context,
                    dbService,
                    bookUuid,
                  ),
          backgroundColor: isDrawingMode ? Colors.grey : Colors.indigo,
          child: const Icon(Icons.draw),
          tooltip: isDrawingMode ? null : l10n.heavyLoadStage2Only,
        ),
        const SizedBox(height: 12),
        // Heavy load test FAB (disabled in drawing mode)
        FloatingActionButton(
          heroTag: 'heavy_load_test',
          onPressed: isDrawingMode
              ? null
              : () => ScheduleTestMenuHelper.showHeavyLoadTestDialog(
                    context,
                    dbService,
                    bookUuid,
                  ),
          backgroundColor: isDrawingMode ? Colors.grey : Colors.deepOrange,
          child: const Icon(Icons.warning_amber),
          tooltip: isDrawingMode ? null : l10n.heavyLoadTest,
        ),
        const SizedBox(height: 12),
        // Clear Cache FAB (experimental - for testing cache mechanism)
        FloatingActionButton(
          heroTag: 'clear_cache',
          onPressed: isDrawingMode
              ? null
              : () {
                  final cubitState = context.read<ScheduleCubit>().state;
                  final events = cubitState is ScheduleLoaded ? cubitState.events : <Event>[];
                  ScheduleTestMenuHelper.showClearCacheDialog(
                    context: context,
                    cacheManager: cacheManager,
                    events: events,
                    dbService: dbService,
                    bookUuid: bookUuid,
                    effectiveDate: getEffectiveDate(),
                    onReloadDrawing: loadDrawing,
                    onPreloadNotes: () {
                      final state = context.read<ScheduleCubit>().state;
                      if (state is ScheduleLoaded) {
                        preloadNotes(state.events);
                      }
                    },
                  );
                },
          backgroundColor: isDrawingMode ? Colors.grey : Colors.amber.shade700,
          child: const Icon(Icons.cached),
          tooltip: isDrawingMode ? null : 'Clear Cache (Test)',
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
      ],
    );
  }
}
