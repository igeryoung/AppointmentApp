import 'package:flutter/material.dart';

import '../../models/event.dart';
import '../../models/event_type.dart';
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
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 60), // Time column width
        ...dates.map((date) => _buildDateColumn(context, date)),
      ],
    );
  }

  /// Build event column for a specific date
  Widget _buildDateColumn(BuildContext context, DateTime date) {
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
}
