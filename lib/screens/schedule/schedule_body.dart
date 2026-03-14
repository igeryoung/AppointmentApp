import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/event.dart';
import '../../models/event_type.dart';
import '../../models/schedule_drawing.dart';
import '../../utils/schedule/schedule_layout_utils.dart';
import '../../widgets/handwriting_canvas.dart';
import '../../widgets/schedule/event_tile.dart';
import '../event_detail/utils/event_type_localizations.dart';
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
  final bool isReadOnlyMode;
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
    this.isReadOnlyMode = false,
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
  static const int _inactiveBottomRows = 1;

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

  bool _isSameDay(DateTime lhs, DateTime rhs) {
    return lhs.year == rhs.year && lhs.month == rhs.month && lhs.day == rhs.day;
  }

  List<Event> _activeEventsForDate(DateTime date) {
    return widget.events
        .where((event) => !event.isRemoved && _isSameDay(event.startTime, date))
        .toList();
  }

  Map<EventType, int> _buildTypeCounts(List<Event> events) {
    final counts = <EventType, int>{};
    for (final event in events) {
      for (final eventType in event.eventTypes.toSet()) {
        counts[eventType] = (counts[eventType] ?? 0) + 1;
      }
    }
    return counts;
  }

  void _showDaySummaryDialog(BuildContext context, DateTime date) {
    final l10n = AppLocalizations.of(context)!;
    final dayEvents = _activeEventsForDate(date);
    final typeCounts = _buildTypeCounts(dayEvents);
    final sortedTypeCounts = typeCounts.entries.toList()
      ..sort((lhs, rhs) {
        final countCompare = rhs.value.compareTo(lhs.value);
        if (countCompare != 0) return countCompare;
        final lhsName = EventTypeLocalizations.getLocalizedEventType(
          context,
          lhs.key,
        );
        final rhsName = EventTypeLocalizations.getLocalizedEventType(
          context,
          rhs.key,
        );
        return lhsName.compareTo(rhsName);
      });

    final locale = Localizations.localeOf(context).toString();
    final dayDisplay = DateFormat('M / d (EEE)', locale).format(date);

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.dayEventSummaryTitle),
              const SizedBox(height: 4),
              Text(
                dayDisplay,
                style: Theme.of(dialogContext).textTheme.bodyMedium,
              ),
            ],
          ),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.dayEventSummaryTotalEvents(dayEvents.length)),
              const SizedBox(height: 12),
              if (sortedTypeCounts.isEmpty)
                Text(l10n.dayEventSummaryNoEvents)
              else ...[
                Text(
                  l10n.dayEventSummaryTypeBreakdown,
                  style: Theme.of(dialogContext).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                ...sortedTypeCounts.map((entry) {
                  final localizedType =
                      EventTypeLocalizations.getLocalizedEventType(
                        dialogContext,
                        entry.key,
                      );
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      l10n.dayEventSummaryTypeCount(localizedType, entry.value),
                    ),
                  );
                }),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.dismiss),
            ),
          ],
        );
      },
    );
  }

  void _startLongPressDrag(
    Event event,
    Offset globalPosition,
    Rect originBounds, {
    required double slotHeight,
    required double dateHeaderHeight,
    required double contentWidth,
    required double activeGridBottom,
  }) {
    if (event.isRemoved) return;

    final hoveredStartTime = _resolveDropStartTime(
      globalPosition: globalPosition,
      slotHeight: slotHeight,
      dateHeaderHeight: dateHeaderHeight,
      contentWidth: contentWidth,
      activeGridBottom: activeGridBottom,
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
    required double activeGridBottom,
  }) {
    if (event.isRemoved) return;

    final draggingEvent = _longPressDraggingEvent;
    if (draggingEvent == null || !_isSameEvent(draggingEvent, event)) return;

    final hoveredStartTime = _resolveDropStartTime(
      globalPosition: globalPosition,
      slotHeight: slotHeight,
      dateHeaderHeight: dateHeaderHeight,
      contentWidth: contentWidth,
      activeGridBottom: activeGridBottom,
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
    required double activeGridBottom,
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
      activeGridBottom: activeGridBottom,
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
    required double activeGridBottom,
  }) {
    final localPosition = _contentLocalFromGlobal(globalPosition);
    if (localPosition == null) return null;

    final gridTop = dateHeaderHeight;
    final gridBottom = activeGridBottom;
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
        // Calculate slot height from all visible rows (active + inactive).
        final dateHeaderHeight = widget.dates.length > 1
            ? _dateHeaderHeight
            : 0.0;
        final totalDisplayRows =
            ScheduleLayoutUtils.totalSlots + _inactiveBottomRows;
        final availableHeightForRows = constraints.maxHeight - dateHeaderHeight;
        final slotHeight = availableHeightForRows / totalDisplayRows;
        final activeGridHeight = slotHeight * ScheduleLayoutUtils.totalSlots;
        final inactiveBottomHeight = slotHeight * _inactiveBottomRows;
        final overlaySize = Size(
          constraints.maxWidth,
          activeGridHeight + inactiveBottomHeight,
        );

        // Keep one extra inactive row under the grid; it zooms/pans with content.
        final contentWidth = constraints.maxWidth;
        final activeGridBottom = dateHeaderHeight + activeGridHeight;
        final contentHeight =
            dateHeaderHeight + activeGridHeight + inactiveBottomHeight;
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
          constrained: false, // Allow extra inactive bottom row in content.
          alignment: Alignment.topLeft,
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
                                isReadOnlyMode: widget.isReadOnlyMode,
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
                                      if (widget.isDrawingMode ||
                                          widget.isReadOnlyMode) {
                                        return;
                                      }
                                      _startLongPressDrag(
                                        event,
                                        globalPosition,
                                        originBounds,
                                        slotHeight: slotHeight,
                                        dateHeaderHeight: dateHeaderHeight,
                                        contentWidth: contentWidth,
                                        activeGridBottom: activeGridBottom,
                                      );
                                    },
                                onLongPressDragUpdate: (event, globalPosition) {
                                  if (widget.isDrawingMode ||
                                      widget.isReadOnlyMode) {
                                    return;
                                  }
                                  _updateLongPressDrag(
                                    event,
                                    globalPosition,
                                    slotHeight: slotHeight,
                                    dateHeaderHeight: dateHeaderHeight,
                                    contentWidth: contentWidth,
                                    activeGridBottom: activeGridBottom,
                                  );
                                },
                                onLongPressDragEnd: (event, globalPosition) {
                                  if (widget.isDrawingMode ||
                                      widget.isReadOnlyMode) {
                                    return;
                                  }
                                  _endLongPressDrag(
                                    event,
                                    globalPosition,
                                    slotHeight: slotHeight,
                                    dateHeaderHeight: dateHeaderHeight,
                                    contentWidth: contentWidth,
                                    activeGridBottom: activeGridBottom,
                                  );
                                },
                                onLongPressDragCancel: (event) {
                                  if (widget.isDrawingMode ||
                                      widget.isReadOnlyMode) {
                                    return;
                                  }
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
                      if (!widget.isReadOnlyMode &&
                          widget.selectedEventForMenu != null &&
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
                          boundarySize: overlaySize,
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
                SizedBox(height: inactiveBottomHeight),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Build date headers for multi-day view
  Widget _buildDateHeaders(BuildContext context, double height) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

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
                      ? theme.colorScheme.primary.withValues(alpha: 0.06)
                      : null,
                  border: Border.all(
                    color: isToday
                        ? theme.colorScheme.primary.withValues(alpha: 0.3)
                        : Colors.grey.shade300,
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              DateFormat(
                                'M / d (EEE)',
                                Localizations.localeOf(context).toString(),
                              ).format(date),
                              style: headerTextStyle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(width: 1),
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: Tooltip(
                                message: l10n.dayEventSummaryTooltip,
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(5),
                                    onTap: () =>
                                        _showDaySummaryDialog(context, date),
                                    child: const Icon(
                                      Icons.summarize_outlined,
                                      size: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isToday)
                        Container(
                          margin: const EdgeInsets.only(top: 1),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.12,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            l10n.today,
                            style:
                                theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 9,
                                ) ??
                                TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 9,
                                ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
