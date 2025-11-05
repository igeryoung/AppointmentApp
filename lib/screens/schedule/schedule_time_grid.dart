import 'package:flutter/material.dart';

import '../../models/event.dart';
import '../../painters/schedule_painters.dart';
import '../../services/time_service.dart';
import '../../utils/schedule/schedule_layout_utils.dart';

/// Schedule time grid with time slots, labels, and current time indicator
class ScheduleTimeGrid extends StatelessWidget {
  final List<DateTime> dates;
  final double slotHeight;
  final bool isDrawingMode;
  final Event? selectedEventForMenu;
  final void Function(DateTime startTime) onCreateEvent;
  final void Function(Event event, DateTime newStartTime) onEventDrop;
  final VoidCallback onCloseEventMenu;

  const ScheduleTimeGrid({
    super.key,
    required this.dates,
    required this.slotHeight,
    required this.isDrawingMode,
    required this.selectedEventForMenu,
    required this.onCreateEvent,
    required this.onEventDrop,
    required this.onCloseEventMenu,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Time slot grid
        Column(
          children: List.generate(
            ScheduleLayoutUtils.totalSlots,
            (index) => _buildTimeSlot(context, index),
          ),
        ),
        // Current time indicator
        _buildCurrentTimeIndicator(),
      ],
    );
  }

  /// Build individual time slot with label and grid cells
  Widget _buildTimeSlot(BuildContext context, int index) {
    final hour = ScheduleLayoutUtils.startHour + (index ~/ 4);
    final minute = (index % 4) * 15;
    final timeStr = '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

    return SizedBox(
      height: slotHeight,
      child: Row(
        children: [
          // Time label
          Container(
            width: 60,
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              timeStr,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 10,
              ),
            ),
          ),
          // Grid cells for each date
          ...dates.map((date) => _buildGridCell(date, hour, minute)),
        ],
      ),
    );
  }

  /// Build grid cell with drag target and tap handling
  Widget _buildGridCell(DateTime date, int hour, int minute) {
    return Expanded(
      child: DragTarget<Event>(
        onWillAcceptWithDetails: (details) => !isDrawingMode,
        onAcceptWithDetails: (details) {
          final newStartTime = DateTime(date.year, date.month, date.day, hour, minute);
          onEventDrop(details.data, newStartTime);
        },
        builder: (context, candidateData, rejectedData) {
          final isHovering = candidateData.isNotEmpty;
          return GestureDetector(
            onTap: () {
              if (selectedEventForMenu != null) {
                onCloseEventMenu();
              } else {
                final startTime = DateTime(date.year, date.month, date.day, hour, minute);
                onCreateEvent(startTime);
              }
            },
            child: Container(
              height: slotHeight,
              decoration: BoxDecoration(
                border: Border.all(
                  color: isHovering ? Colors.blue.shade300 : Colors.grey.shade400,
                  width: isHovering ? 2.0 : 0.5,
                ),
                color: isHovering ? Colors.blue.shade50.withValues(alpha: 0.3) : null,
              ),
            ),
          );
        },
      ),
    );
  }

  /// Build current time indicator
  Widget _buildCurrentTimeIndicator() {
    final now = TimeService.instance.now();

    // Only show indicator if current time is within visible range
    if (now.hour < ScheduleLayoutUtils.startHour ||
        now.hour >= ScheduleLayoutUtils.endHour) {
      return const SizedBox.shrink();
    }

    // Calculate position based on current time
    final yPosition = ScheduleLayoutUtils.calculateEventTopPosition(now, slotHeight);

    return Positioned(
      top: yPosition,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Row(
          children: [
            const SizedBox(width: 60), // Time column offset
            ...dates.map((date) {
              final isToday = date.year == now.year &&
                  date.month == now.month &&
                  date.day == now.day;

              return Expanded(
                child: isToday
                    ? const CustomPaint(
                        painter: CurrentTimeLinePainter(),
                        size: Size(double.infinity, 2),
                      )
                    : const SizedBox.shrink(),
              );
            }),
          ],
        ),
      ),
    );
  }
}
