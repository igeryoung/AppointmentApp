import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/event.dart';
import '../../models/event_type.dart';
import '../../models/schedule_drawing.dart';
import '../../utils/schedule/schedule_layout_utils.dart';
import '../../widgets/handwriting_canvas.dart';
import '../../widgets/schedule/event_tile.dart';
import 'schedule_context_menu.dart';
import 'schedule_drawing_overlay.dart';
import 'schedule_event_overlay.dart';
import 'schedule_time_grid.dart';

/// Schedule body that composes all schedule components
class ScheduleBody extends StatefulWidget {
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
  final VoidCallback? onScheduleNextAppointment;
  final VoidCallback? onRemove;
  final VoidCallback? onDelete;
  final Function(bool)? onCheckedChanged;

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
    this.onScheduleNextAppointment,
    this.onRemove,
    this.onDelete,
    this.onCheckedChanged,
  });

  @override
  State<ScheduleBody> createState() => _ScheduleBodyState();
}

class _ScheduleBodyState extends State<ScheduleBody> {
  static const double _timeColumnWidth = 60.0;
  static const double _dateHeaderHeight = 50.0;

  final GlobalKey _contentKey = GlobalKey();
  Event? _longPressDraggingEvent;
  DateTime? _hoveredDropStartTime;
  Offset? _dragPointerGlobalPosition;
  Rect? _dragOriginBounds;
  Offset? _dragAnchorOffset;

  bool _isSameEvent(Event lhs, Event rhs) {
    if (lhs.id != null && rhs.id != null) {
      return lhs.id == rhs.id;
    }
    return identical(lhs, rhs);
  }

  void _startLongPressDrag(
    Event event,
    Offset globalPosition,
    Rect originBounds, {
    required double slotHeight,
    required double dateHeaderHeight,
    required double contentWidth,
    required double contentHeight,
  }) {
    if (event.isRemoved) return;

    final hoveredStartTime = _resolveDropStartTime(
      globalPosition: globalPosition,
      slotHeight: slotHeight,
      dateHeaderHeight: dateHeaderHeight,
      contentWidth: contentWidth,
      contentHeight: contentHeight,
    );
    widget.onCloseEventMenu();
    final rawAnchor = globalPosition - originBounds.topLeft;
    final clampedAnchor = Offset(
      rawAnchor.dx.clamp(0.0, originBounds.width),
      rawAnchor.dy.clamp(0.0, originBounds.height),
    );
    setState(() {
      _longPressDraggingEvent = event;
      _hoveredDropStartTime = hoveredStartTime;
      _dragPointerGlobalPosition = globalPosition;
      _dragOriginBounds = originBounds;
      _dragAnchorOffset = clampedAnchor;
    });
  }

  void _updateLongPressDrag(
    Event event,
    Offset globalPosition, {
    required double slotHeight,
    required double dateHeaderHeight,
    required double contentWidth,
    required double contentHeight,
  }) {
    if (event.isRemoved) return;

    final draggingEvent = _longPressDraggingEvent;
    if (draggingEvent == null || !_isSameEvent(draggingEvent, event)) return;

    final hoveredStartTime = _resolveDropStartTime(
      globalPosition: globalPosition,
      slotHeight: slotHeight,
      dateHeaderHeight: dateHeaderHeight,
      contentWidth: contentWidth,
      contentHeight: contentHeight,
    );
    setState(() {
      _hoveredDropStartTime = hoveredStartTime;
      _dragPointerGlobalPosition = globalPosition;
    });
  }

  void _endLongPressDrag(
    Event event,
    Offset globalPosition, {
    required double slotHeight,
    required double dateHeaderHeight,
    required double contentWidth,
    required double contentHeight,
  }) {
    if (event.isRemoved) return;

    final draggingEvent = _longPressDraggingEvent;
    final isActiveDrag =
        draggingEvent != null && _isSameEvent(draggingEvent, event);

    setState(() {
      _longPressDraggingEvent = null;
      _hoveredDropStartTime = null;
      _dragPointerGlobalPosition = null;
      _dragOriginBounds = null;
      _dragAnchorOffset = null;
    });

    if (!isActiveDrag) return;

    final dropStartTime = _resolveDropStartTime(
      globalPosition: globalPosition,
      slotHeight: slotHeight,
      dateHeaderHeight: dateHeaderHeight,
      contentWidth: contentWidth,
      contentHeight: contentHeight,
    );
    if (dropStartTime != null) {
      widget.onEventDrop(event, dropStartTime);
    }
  }

  Offset? _contentLocalFromGlobal(Offset globalPosition) {
    final renderBox =
        _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return null;
    return renderBox.globalToLocal(globalPosition);
  }

  Offset _resolveMenuPosition({
    required Offset rawPosition,
    required double dateHeaderHeight,
  }) {
    // Event tiles report global pointer coordinates; the context menu is
    // positioned inside the grid stack (local coordinates below date header).
    final local = _contentLocalFromGlobal(rawPosition);
    if (local == null) return rawPosition;
    return Offset(local.dx, local.dy - dateHeaderHeight);
  }

  DateTime? _resolveDropStartTime({
    required Offset globalPosition,
    required double slotHeight,
    required double dateHeaderHeight,
    required double contentWidth,
    required double contentHeight,
  }) {
    final localPosition = _contentLocalFromGlobal(globalPosition);
    if (localPosition == null) return null;

    final gridTop = dateHeaderHeight;
    final gridBottom = contentHeight;
    final gridLeft = _timeColumnWidth;
    final gridRight = contentWidth;

    if (localPosition.dx < gridLeft || localPosition.dx >= gridRight) {
      return null;
    }
    if (localPosition.dy < gridTop || localPosition.dy >= gridBottom) {
      return null;
    }

    final dayAreaWidth = contentWidth - _timeColumnWidth;
    if (dayAreaWidth <= 0 || widget.dates.isEmpty) return null;

    final columnWidth = dayAreaWidth / widget.dates.length;
    if (columnWidth <= 0) return null;

    final dayIndex = ((localPosition.dx - _timeColumnWidth) / columnWidth)
        .floor()
        .clamp(0, widget.dates.length - 1);

    final yInGrid = localPosition.dy - dateHeaderHeight;
    final slotIndex = (yInGrid / slotHeight).floor().clamp(
      0,
      ScheduleLayoutUtils.totalSlots - 1,
    );

    final hour = ScheduleLayoutUtils.startHour + (slotIndex ~/ 4);
    final minute = (slotIndex % 4) * 15;
    final date = widget.dates[dayIndex];

    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  void _cancelLongPressDrag(Event event) {
    if (event.isRemoved) return;

    final draggingEvent = _longPressDraggingEvent;
    if (draggingEvent == null || !_isSameEvent(draggingEvent, event)) return;
    setState(() {
      _longPressDraggingEvent = null;
      _hoveredDropStartTime = null;
      _dragPointerGlobalPosition = null;
      _dragOriginBounds = null;
      _dragAnchorOffset = null;
    });
  }

  Widget _buildFloatingDraggedEventPreview(
    double slotHeight, {
    required double dateHeaderHeight,
  }) {
    final event = _longPressDraggingEvent;
    final pointer = _dragPointerGlobalPosition;
    final originBounds = _dragOriginBounds;
    final anchorOffset = _dragAnchorOffset;
    if (event == null ||
        pointer == null ||
        originBounds == null ||
        anchorOffset == null) {
      return const SizedBox.shrink();
    }

    final localPointer = _contentLocalFromGlobal(pointer);
    if (localPointer == null) return const SizedBox.shrink();

    final left = localPointer.dx - anchorOffset.dx;
    final top = localPointer.dy - dateHeaderHeight - anchorOffset.dy;
    final width = originBounds.width > 0 ? originBounds.width : 1.0;
    final height = originBounds.height > 0 ? originBounds.height : slotHeight;

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: ScheduleEventTileHelper.buildFloatingDragPreview(
          context: context,
          event: event,
          slotHeight: slotHeight,
          events: widget.events,
          getEventTypeColor: widget.getEventTypeColor,
          width: width,
          height: height,
          hasHandwriting: event.hasNote,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate dynamic slot height to fit screen perfectly
        final dateHeaderHeight = widget.dates.length > 1
            ? _dateHeaderHeight
            : 0.0;
        final availableHeightForSlots =
            constraints.maxHeight - dateHeaderHeight;
        final slotHeight =
            availableHeightForSlots / ScheduleLayoutUtils.totalSlots;

        // Content dimensions - exactly match screen
        final contentWidth = constraints.maxWidth;
        final contentHeight = constraints.maxHeight;
        final resolvedMenuPosition = widget.menuPosition != null
            ? _resolveMenuPosition(
                rawPosition: widget.menuPosition!,
                dateHeaderHeight: dateHeaderHeight,
              )
            : null;

        return InteractiveViewer(
          transformationController: widget.transformationController,
          minScale: 1.0, // Cannot zoom out - this IS the most zoomed out
          maxScale: 4.0, // Max zoom in
          boundaryMargin: EdgeInsets.zero, // Strict boundaries - no blank space
          constrained: true, // Respect size constraints
          panEnabled: !widget.isDrawingMode, // Disable pan when drawing
          scaleEnabled: true, // Always allow pinch zoom
          child: SizedBox(
            key: _contentKey,
            width: contentWidth,
            height: contentHeight,
            child: Column(
              children: [
                // Date headers - zoom/pan with content
                if (widget.dates.length > 1)
                  _buildDateHeaders(context, dateHeaderHeight),
                // Time slots + events + drawing overlay
                Expanded(
                  child: Stack(
                    children: [
                      // Schedule grid (dimmed when in drawing mode)
                      Opacity(
                        opacity: widget.isDrawingMode ? 0.6 : 1.0,
                        child: AbsorbPointer(
                          absorbing: widget
                              .isDrawingMode, // Disable event interactions in drawing mode
                          child: Stack(
                            children: [
                              // Time slot grid
                              ScheduleTimeGrid(
                                dates: widget.dates,
                                slotHeight: slotHeight,
                                isDrawingMode: widget.isDrawingMode,
                                selectedEventForMenu:
                                    widget.selectedEventForMenu,
                                hoveredDropStartTime: _hoveredDropStartTime,
                                onCreateEvent: widget.onCreateEvent,
                                onEventDrop: widget.onEventDrop,
                                onCloseEventMenu: widget.onCloseEventMenu,
                              ),
                              // Events overlay
                              ScheduleEventOverlay(
                                dates: widget.dates,
                                slotHeight: slotHeight,
                                allEvents: widget.events,
                                showOldEvents: widget.showOldEvents,
                                getEventTypeColor: widget.getEventTypeColor,
                                onEditEvent: widget.onEditEvent,
                                onShowEventContextMenu:
                                    widget.onShowEventContextMenu,
                                onLongPressDragStart:
                                    (event, globalPosition, originBounds) {
                                      if (widget.isDrawingMode) return;
                                      _startLongPressDrag(
                                        event,
                                        globalPosition,
                                        originBounds,
                                        slotHeight: slotHeight,
                                        dateHeaderHeight: dateHeaderHeight,
                                        contentWidth: contentWidth,
                                        contentHeight: contentHeight,
                                      );
                                    },
                                onLongPressDragUpdate: (event, globalPosition) {
                                  if (widget.isDrawingMode) return;
                                  _updateLongPressDrag(
                                    event,
                                    globalPosition,
                                    slotHeight: slotHeight,
                                    dateHeaderHeight: dateHeaderHeight,
                                    contentWidth: contentWidth,
                                    contentHeight: contentHeight,
                                  );
                                },
                                onLongPressDragEnd: (event, globalPosition) {
                                  if (widget.isDrawingMode) return;
                                  _endLongPressDrag(
                                    event,
                                    globalPosition,
                                    slotHeight: slotHeight,
                                    dateHeaderHeight: dateHeaderHeight,
                                    contentWidth: contentWidth,
                                    contentHeight: contentHeight,
                                  );
                                },
                                onLongPressDragCancel: (event) {
                                  if (widget.isDrawingMode) return;
                                  _cancelLongPressDrag(event);
                                },
                                draggingEvent: _longPressDraggingEvent,
                                selectedEventForMenu:
                                    widget.selectedEventForMenu,
                              ),
                            ],
                          ),
                        ),
                      ),
                      _buildFloatingDraggedEventPreview(
                        slotHeight,
                        dateHeaderHeight: dateHeaderHeight,
                      ),
                      // Drawing overlay
                      ScheduleDrawingOverlay(
                        canvasKey: widget.canvasKey,
                        currentDrawing: widget.currentDrawing,
                        isDrawingMode: widget.isDrawingMode,
                        showDrawing: widget.showDrawing,
                        onStrokesChanged: widget.onDrawingStrokesChanged,
                      ),
                      // Context menu overlay
                      if (widget.selectedEventForMenu != null &&
                          resolvedMenuPosition != null &&
                          widget.onChangeType != null &&
                          widget.onChangeTime != null &&
                          widget.onScheduleNextAppointment != null &&
                          widget.onRemove != null &&
                          widget.onDelete != null &&
                          widget.onCheckedChanged != null)
                        ScheduleContextMenu(
                          event: widget.selectedEventForMenu!,
                          position: resolvedMenuPosition,
                          onClose: widget.onCloseEventMenu,
                          onChangeType: widget.onChangeType!,
                          onChangeTime: widget.onChangeTime!,
                          onScheduleNextAppointment:
                              widget.onScheduleNextAppointment!,
                          onRemove: widget.onRemove!,
                          onDelete: widget.onDelete!,
                          onCheckedChanged: widget.onCheckedChanged!,
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
    final theme = Theme.of(context);
    const todayLabel = 'Today';

    return SizedBox(
      height: height,
      child: Row(
        children: [
          const SizedBox(width: 60), // Time column width
          ...widget.dates.map((date) {
            final isToday = ScheduleLayoutUtils.isViewingToday(date);
            final headerTextStyle = theme.textTheme.titleSmall?.copyWith(
              fontSize: (theme.textTheme.titleSmall?.fontSize ?? 14) * 1.2,
              fontWeight: isToday ? FontWeight.w600 : FontWeight.normal,
              color: isToday ? theme.colorScheme.primary : null,
            );

            return Expanded(
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isToday
                      ? theme.colorScheme.primary.withOpacity(0.06)
                      : null,
                  border: Border.all(
                    color: isToday
                        ? theme.colorScheme.primary.withOpacity(0.3)
                        : Colors.grey.shade300,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      DateFormat(
                        'M / d (EEE)',
                        Localizations.localeOf(context).toString(),
                      ).format(date),
                      style: headerTextStyle,
                    ),
                    if (isToday)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          todayLabel,
                          style:
                              theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ) ??
                              TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 10,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
