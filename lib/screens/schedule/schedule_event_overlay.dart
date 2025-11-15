import 'package:flutter/material.dart';

import '../../models/event.dart';
import '../../models/event_type.dart';
import '../../models/schedule_drawing.dart';
import '../../painters/schedule_painters.dart';
import '../../utils/schedule/schedule_layout_utils.dart';
import '../../widgets/schedule/event_tile.dart';

/// Event overlay that renders positioned events on the schedule grid
class ScheduleEventOverlay extends StatelessWidget {
  final List<DateTime> dates;
  final double slotHeight;
  final List<Event> allEvents;
  final bool showOldEvents;
  final Color Function(BuildContext, EventType) getEventTypeColor;
  final void Function(Event) onEditEvent;
  final void Function(Event, Offset) onShowEventContextMenu;
  final Event? selectedEventForMenu;
  final ScheduleDrawing? currentDrawing;

  const ScheduleEventOverlay({
    super.key,
    required this.dates,
    required this.slotHeight,
    required this.allEvents,
    required this.showOldEvents,
    required this.getEventTypeColor,
    required this.onEditEvent,
    required this.onShowEventContextMenu,
    required this.selectedEventForMenu,
    this.currentDrawing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 60), // Time column width
        ...dates.asMap().entries.map((entry) {
          final dateIndex = entry.key;
          final date = entry.value;
          return _buildDateColumn(context, date, dateIndex);
        }),
      ],
    );
  }

  /// Build event column for a specific date
  Widget _buildDateColumn(BuildContext context, DateTime date, int dateIndex) {
    final dateEvents = ScheduleLayoutUtils.getEventsForDate(
      date,
      allEvents,
      showOldEvents,
    );

    return Expanded(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth - 4; // Account for padding/borders

          // Calculate event positions using the layout algorithm
          final positionedEvents = ScheduleLayoutUtils.calculateEventPositions(
            dateEvents: dateEvents,
            availableWidth: availableWidth,
            slotHeight: slotHeight,
          );

          // Build positioned widgets
          final List<Widget> positionedWidgets = [];

          for (final positioned in positionedEvents) {
            final leftPosition = positioned.horizontalPosition * positioned.width;

            // Calculate absolute screen coordinates for stroke detection
            // Account for time column (60px) and date column offset
            final absoluteLeft = 60.0 + (dateIndex * constraints.maxWidth) + leftPosition;

            // Check if event has handwriting strokes
            final hasHandwriting = _hasStrokesInBounds(
              drawing: currentDrawing,
              eventLeft: absoluteLeft,
              eventTop: positioned.topPosition,
              eventWidth: positioned.width,
              eventHeight: positioned.height,
            );

            positionedWidgets.add(
              Positioned(
                top: positioned.topPosition,
                left: leftPosition,
                width: positioned.width,
                height: positioned.height,
                child: ScheduleEventTileHelper.buildEventTile(
                  context: context,
                  event: positioned.event,
                  slotHeight: slotHeight,
                  events: allEvents,
                  getEventTypeColor: getEventTypeColor,
                  onTap: () => onEditEvent(positioned.event),
                  onLongPress: (offset) => onShowEventContextMenu(positioned.event, offset),
                  isMenuOpen: selectedEventForMenu?.id == positioned.event.id,
                  hasHandwriting: hasHandwriting,
                  dottedBorderPainter: (color) => CustomPaint(
                    painter: DottedBorderPainter(color: color, strokeWidth: 1),
                  ),
                ),
              ),
            );
          }

          return Stack(
            clipBehavior: Clip.none,
            children: positionedWidgets,
          );
        },
      ),
    );
  }

  /// Check if drawing has strokes within event bounds
  bool _hasStrokesInBounds({
    required ScheduleDrawing? drawing,
    required double eventLeft,
    required double eventTop,
    required double eventWidth,
    required double eventHeight,
  }) {
    if (drawing == null || drawing.strokes.isEmpty) return false;

    final eventRight = eventLeft + eventWidth;
    final eventBottom = eventTop + eventHeight;

    // Check if any stroke point falls within event bounds
    for (final stroke in drawing.strokes) {
      for (final point in stroke.points) {
        if (point.dx >= eventLeft &&
            point.dx <= eventRight &&
            point.dy >= eventTop &&
            point.dy <= eventBottom) {
          return true;
        }
      }
    }

    return false;
  }
}
