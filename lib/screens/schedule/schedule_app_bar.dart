import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../cubits/schedule_cubit.dart';
import '../../cubits/schedule_state.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/schedule/schedule_layout_utils.dart';

/// Schedule screen app bar with date navigation and controls
class ScheduleAppBar extends StatelessWidget implements PreferredSizeWidget {
  final DateTime selectedDate;
  final VoidCallback onPreviousDay;
  final VoidCallback onNextDay;
  final Future<void> Function(DateTime) onDateSelected;
  final VoidCallback onGoToToday;

  const ScheduleAppBar({
    super.key,
    required this.selectedDate,
    required this.onPreviousDay,
    required this.onNextDay,
    required this.onDateSelected,
    required this.onGoToToday,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AppBar(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Date navigation - Previous button
          IconButton(
            onPressed: onPreviousDay,
            icon: const Icon(Icons.chevron_left, size: 18),
            iconSize: 18,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
          ),
          const SizedBox(width: 4),
          // Date display
          GestureDetector(
            onTap: () => _showDatePicker(context),
            child: Text(
              _getDateDisplayText(context),
              style: const TextStyle(
                color: Colors.black,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 4),
          // Date navigation - Next button
          IconButton(
            onPressed: onNextDay,
            icon: const Icon(Icons.chevron_right, size: 18),
            iconSize: 18,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
      actions: [
        // Toggle old events visibility
        BlocBuilder<ScheduleCubit, ScheduleState>(
          builder: (context, state) {
            final showOldEvents = state is ScheduleLoaded ? state.showOldEvents : true;
            return IconButton(
              icon: Icon(showOldEvents ? Icons.visibility : Icons.visibility_off),
              onPressed: () {
                context.read<ScheduleCubit>().toggleOldEvents();
              },
              tooltip: showOldEvents ? l10n.hideOldEvents : l10n.showOldEvents,
            );
          },
        ),
        // Go to today button
        IconButton(
          icon: const Icon(Icons.today),
          onPressed: onGoToToday,
          tooltip: l10n.goToToday,
        ),
      ],
    );
  }

  /// Show date picker dialog
  Future<void> _showDatePicker(BuildContext context) async {
    final date = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) {
      await onDateSelected(date);
    }
  }

  /// Get date display text for 3-day window
  String _getDateDisplayText(BuildContext context) {
    final windowStart = ScheduleLayoutUtils.get3DayWindowStart(selectedDate);
    final windowEnd = windowStart.add(const Duration(days: 2));
    final locale = Localizations.localeOf(context).toString();
    return '${DateFormat('MMM d', locale).format(windowStart)} - ${DateFormat('MMM d, y', locale).format(windowEnd)}';
  }
}
