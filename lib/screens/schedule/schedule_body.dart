import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/event.dart';
import '../../models/event_type.dart';
import '../../models/schedule_drawing.dart';
import '../../utils/schedule/schedule_layout_utils.dart';
import '../../widgets/handwriting_canvas.dart';
import 'schedule_context_menu.dart';
import 'schedule_drawing_overlay.dart';
import 'schedule_event_overlay.dart';
import 'schedule_time_grid.dart';

/// Schedule body that composes all schedule components
class ScheduleBody extends StatelessWidget {
  final List<DateTime> dates;
  final List<Event> events;
  final bool showOldEvents;
  final bool showDrawing;
  final bool isDrawingMode;
  final GlobalKey<HandwritingCanvasState> canvasKey;
  final ScheduleDrawing? currentDrawing;
  final TransformationController transformationController;
  final Color Function(BuildContext, EventType) getEventTypeColor;
  final void Function(Event) onEditEvent;
  final void Function(Event, Offset) onShowEventContextMenu;
  final void Function(DateTime startTime) onCreateEvent;
  final void Function(Event event, DateTime newStartTime) onEventDrop;
  final VoidCallback onCloseEventMenu;
  final VoidCallback onDrawingStrokesChanged;
  final Event? selectedEventForMenu;
  final Offset? menuPosition;
  final VoidCallback? onChangeType;
  final VoidCallback? onChangeTime;
  final VoidCallback? onRemove;
  final VoidCallback? onDelete;

  const ScheduleBody({
    super.key,
    required this.dates,
    required this.events,
    required this.showOldEvents,
    required this.showDrawing,
    required this.isDrawingMode,
    required this.canvasKey,
    required this.currentDrawing,
    required this.transformationController,
    required this.getEventTypeColor,
    required this.onEditEvent,
    required this.onShowEventContextMenu,
    required this.onCreateEvent,
    required this.onEventDrop,
    required this.onCloseEventMenu,
    required this.onDrawingStrokesChanged,
    this.selectedEventForMenu,
    this.menuPosition,
    this.onChangeType,
    this.onChangeTime,
    this.onRemove,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate dynamic slot height to fit screen perfectly
        final dateHeaderHeight = dates.length > 1 ? 50.0 : 0.0;
        final availableHeightForSlots = constraints.maxHeight - dateHeaderHeight;
        final slotHeight = availableHeightForSlots / ScheduleLayoutUtils.totalSlots;

        // Content dimensions - exactly match screen
        final contentWidth = constraints.maxWidth;
        final contentHeight = constraints.maxHeight;

        return InteractiveViewer(
          transformationController: transformationController,
          minScale: 1.0, // Cannot zoom out - this IS the most zoomed out
          maxScale: 4.0, // Max zoom in
          boundaryMargin: EdgeInsets.zero, // Strict boundaries - no blank space
          constrained: true, // Respect size constraints
          panEnabled: !isDrawingMode, // Disable pan when drawing
          scaleEnabled: true, // Always allow pinch zoom
          child: SizedBox(
            width: contentWidth,
            height: contentHeight,
            child: Column(
              children: [
                // Date headers - zoom/pan with content
                if (dates.length > 1) _buildDateHeaders(context, dateHeaderHeight),
                // Time slots + events + drawing overlay
                Expanded(
                  child: Stack(
                    children: [
                      // Schedule grid (dimmed when in drawing mode)
                      Opacity(
                        opacity: isDrawingMode ? 0.6 : 1.0,
                        child: AbsorbPointer(
                          absorbing: isDrawingMode, // Disable event interactions in drawing mode
                          child: Stack(
                            children: [
                              // Time slot grid
                              ScheduleTimeGrid(
                                dates: dates,
                                slotHeight: slotHeight,
                                isDrawingMode: isDrawingMode,
                                selectedEventForMenu: selectedEventForMenu,
                                onCreateEvent: onCreateEvent,
                                onEventDrop: onEventDrop,
                                onCloseEventMenu: onCloseEventMenu,
                              ),
                              // Events overlay
                              ScheduleEventOverlay(
                                dates: dates,
                                slotHeight: slotHeight,
                                allEvents: events,
                                showOldEvents: showOldEvents,
                                getEventTypeColor: getEventTypeColor,
                                onEditEvent: onEditEvent,
                                onShowEventContextMenu: onShowEventContextMenu,
                                selectedEventForMenu: selectedEventForMenu,
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Drawing overlay
                      ScheduleDrawingOverlay(
                        canvasKey: canvasKey,
                        currentDrawing: currentDrawing,
                        isDrawingMode: isDrawingMode,
                        showDrawing: showDrawing,
                        onStrokesChanged: onDrawingStrokesChanged,
                      ),
                      // Context menu overlay
                      if (selectedEventForMenu != null &&
                          menuPosition != null &&
                          onChangeType != null &&
                          onChangeTime != null &&
                          onRemove != null &&
                          onDelete != null)
                        ScheduleContextMenu(
                          event: selectedEventForMenu!,
                          position: menuPosition!,
                          onClose: onCloseEventMenu,
                          onChangeType: onChangeType!,
                          onChangeTime: onChangeTime!,
                          onRemove: onRemove!,
                          onDelete: onDelete!,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Build date headers for multi-day view
  Widget _buildDateHeaders(BuildContext context, double height) {
    return SizedBox(
      height: height,
      child: Row(
        children: [
          const SizedBox(width: 60), // Time column width
          ...dates.map((date) => Expanded(
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    DateFormat('M / d (EEE)', Localizations.localeOf(context).toString()).format(date),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontSize: (Theme.of(context).textTheme.titleSmall?.fontSize ?? 14) * 1.2,
                    ),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}
