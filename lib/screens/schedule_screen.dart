import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../cubits/schedule_cubit.dart';
import '../cubits/schedule_state.dart';
import '../l10n/app_localizations.dart';
import '../models/book.dart';
import '../models/event.dart';
import '../models/schedule_drawing.dart';
import '../services/database_service_interface.dart';
import '../services/service_locator.dart';
import '../utils/schedule/schedule_layout_utils.dart';
import '../widgets/schedule/drawing_toolbar.dart';
import '../widgets/schedule/fab_menu.dart';
import 'schedule/schedule_body.dart';
import 'schedule/schedule_controller.dart';

/// Schedule screen supporting 2-day and 3-day views
class ScheduleScreen extends StatefulWidget {
  final Book book;

  const ScheduleScreen({super.key, required this.book});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen>
    with WidgetsBindingObserver {
  late final IDatabaseService _dbService;
  late final ScheduleController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dbService = getIt<IDatabaseService>();
    _controller = ScheduleController(
      book: widget.book,
      dbService: _dbService,
      contextProvider: () => context,
    );
    _controller.initialize(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _controller.handleLifecycle(state, context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return BlocListener<ScheduleCubit, ScheduleState>(
          listener: (context, state) {
            if (state is ScheduleLoaded) {
              _controller.handleLoadedState(state, context);
            }
          },
          child: PopScope(
            canPop: false,
            onPopInvokedWithResult: (bool didPop, dynamic result) async {
              if (didPop) return;

              if (_controller.isDrawingMode) {
                await _controller.saveDrawing(context);
              }

              if (mounted) {
                Navigator.of(context).pop();
              }
            },
            child: Stack(
              children: [
                Scaffold(
                  appBar: AppBar(
                    title: Padding(
                      padding: const EdgeInsets.only(left: 160.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: () => _controller.dateService
                                ?.navigate180DaysPrevious(),
                            icon: const Text(
                              '-180',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            iconSize: 18,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 28,
                            ),
                            padding: EdgeInsets.zero,
                            tooltip: '-180 days',
                          ),
                          IconButton(
                            onPressed: () => _controller.dateService
                                ?.navigate90DaysPrevious(),
                            icon: const Text(
                              '-90',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            iconSize: 18,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 28,
                            ),
                            padding: EdgeInsets.zero,
                            tooltip: '-90 days',
                          ),
                          BlocBuilder<ScheduleCubit, ScheduleState>(
                            builder: (context, state) {
                              final viewMode = state is ScheduleLoaded
                                  ? state.viewMode
                                  : ScheduleDrawing.VIEW_MODE_2DAY;
                              final windowSize =
                                  viewMode == ScheduleDrawing.VIEW_MODE_2DAY
                                  ? 2
                                  : 3;
                              return IconButton(
                                onPressed: () => _controller.dateService
                                    ?.navigatePagePrevious(),
                                icon: const Icon(Icons.chevron_left, size: 18),
                                iconSize: 18,
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                                padding: EdgeInsets.zero,
                                tooltip: '-$windowSize days',
                              );
                            },
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => _controller.dateService
                                ?.showDatePickerDialog(context),
                            child: Text(
                              _controller.dateService?.getDateDisplayText(
                                    context,
                                  ) ??
                                  '',
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
                          BlocBuilder<ScheduleCubit, ScheduleState>(
                            builder: (context, state) {
                              final viewMode = state is ScheduleLoaded
                                  ? state.viewMode
                                  : ScheduleDrawing.VIEW_MODE_2DAY;
                              final windowSize =
                                  viewMode == ScheduleDrawing.VIEW_MODE_2DAY
                                  ? 2
                                  : 3;
                              return IconButton(
                                onPressed: () =>
                                    _controller.dateService?.navigatePageNext(),
                                icon: const Icon(Icons.chevron_right, size: 18),
                                iconSize: 18,
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                                padding: EdgeInsets.zero,
                                tooltip: '+$windowSize days',
                              );
                            },
                          ),
                          IconButton(
                            onPressed: () =>
                                _controller.dateService?.navigate90DaysNext(),
                            icon: const Text(
                              '+90',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            iconSize: 18,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 28,
                            ),
                            padding: EdgeInsets.zero,
                            tooltip: '+90 days',
                          ),
                          IconButton(
                            onPressed: () =>
                                _controller.dateService?.navigate180DaysNext(),
                            icon: const Text(
                              '+180',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            iconSize: 18,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 28,
                            ),
                            padding: EdgeInsets.zero,
                            tooltip: '+180 days',
                          ),
                        ],
                      ),
                    ),
                    actions: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: _controller.isNavigating
                              ? const CircularProgressIndicator(strokeWidth: 2)
                              : const SizedBox.shrink(),
                        ),
                      ),
                      BlocBuilder<ScheduleCubit, ScheduleState>(
                        builder: (context, state) {
                          final viewMode = state is ScheduleLoaded
                              ? state.viewMode
                              : ScheduleDrawing.VIEW_MODE_2DAY;
                          return PopupMenuButton<int>(
                            icon: const Icon(Icons.view_day),
                            offset: const Offset(0, 40),
                            onSelected: (int newViewMode) async {
                              _controller.setViewMode(newViewMode);
                              await context
                                  .read<ScheduleCubit>()
                                  .changeViewMode(newViewMode);
                            },
                            itemBuilder: (BuildContext context) =>
                                <PopupMenuEntry<int>>[
                                  PopupMenuItem<int>(
                                    value: ScheduleDrawing.VIEW_MODE_2DAY,
                                    child: Row(
                                      children: [
                                        if (viewMode ==
                                            ScheduleDrawing.VIEW_MODE_2DAY)
                                          const Icon(Icons.check, size: 16)
                                        else
                                          const SizedBox(width: 16),
                                        const SizedBox(width: 8),
                                        Text(l10n.twoDays),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem<int>(
                                    value: ScheduleDrawing.VIEW_MODE_3DAY,
                                    child: Row(
                                      children: [
                                        if (viewMode ==
                                            ScheduleDrawing.VIEW_MODE_3DAY)
                                          const Icon(Icons.check, size: 16)
                                        else
                                          const SizedBox(width: 16),
                                        const SizedBox(width: 8),
                                        Text(l10n.threeDays),
                                      ],
                                    ),
                                  ),
                                ],
                          );
                        },
                      ),
                      BlocBuilder<ScheduleCubit, ScheduleState>(
                        builder: (context, state) {
                          final showDrawing = state is ScheduleLoaded
                              ? state.showDrawing
                              : true;
                          return IconButton(
                            icon: Icon(
                              showDrawing ? Icons.brush : Icons.brush_outlined,
                            ),
                            onPressed: () {
                              context.read<ScheduleCubit>().toggleDrawing();
                            },
                            tooltip: showDrawing
                                ? l10n.hideDrawing
                                : l10n.showDrawing,
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.today),
                        onPressed: () async {
                          await _controller.dateService?.jumpToToday();
                          _controller.panToCurrentTime();
                        },
                        tooltip: l10n.goToToday,
                      ),
                    ],
                  ),
                  body: BlocBuilder<ScheduleCubit, ScheduleState>(
                    builder: (context, state) {
                      if (state is ScheduleError) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                size: 48,
                                color: Colors.red,
                              ),
                              const SizedBox(height: 16),
                              Text('Error: ${state.message}'),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () =>
                                    context.read<ScheduleCubit>().loadEvents(),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        );
                      }

                      final isLoading = state is ScheduleLoading;
                      final events = state is ScheduleLoaded
                          ? state.events
                          : <Event>[];
                      final showOldEvents = state is ScheduleLoaded
                          ? state.showOldEvents
                          : true;
                      final showDrawing = state is ScheduleLoaded
                          ? state.showDrawing
                          : true;
                      final pendingNextAppointment = state is ScheduleLoaded
                          ? state.pendingNextAppointment
                          : null;
                      final viewMode = state is ScheduleLoaded
                          ? state.viewMode
                          : ScheduleDrawing.VIEW_MODE_2DAY;

                      return Stack(
                        children: [
                          Column(
                            children: [
                              Expanded(
                                child: isLoading
                                    ? const Center(
                                        child: CircularProgressIndicator(),
                                      )
                                    : _build3DayView(
                                        _controller,
                                        events,
                                        showOldEvents,
                                        showDrawing,
                                        pendingNextAppointment,
                                        viewMode,
                                      ),
                              ),
                            ],
                          ),
                          if (_controller.isDrawingMode)
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child:
                                  ScheduleDrawingToolbarHelper.buildDrawingToolbar(
                                    context: context,
                                    getCanvasKey:
                                        _controller.getCanvasKeyForCurrentPage,
                                    onCanvasStateChange: () =>
                                        _controller.markNeedsBuild(),
                                    saveDrawing: () =>
                                        _controller.saveDrawing(context),
                                  ),
                            ),
                        ],
                      );
                    },
                  ),
                  floatingActionButton: ScheduleFabMenuHelper.buildFabMenu(
                    context: context,
                    isMenuVisible: _controller.isFabMenuVisible,
                    onToggleMenu: _controller.toggleFabMenu,
                    isDrawingMode: _controller.isDrawingMode,
                    isViewingToday: () =>
                        _controller.dateService?.isViewingToday() ?? false,
                    selectedDate: _controller.selectedDate,
                    saveDrawing: () => _controller.saveDrawing(context),
                    loadDrawing: () => _controller.loadDrawing(),
                    toggleDrawingMode: () =>
                        _controller.toggleDrawingMode(context),
                    createEvent: () => _controller.eventService?.createEvent(),
                    bookUuid: widget.book.uuid,
                    onDateChange: _controller.changeDateTo,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _build3DayView(
    ScheduleController controller,
    List<Event> events,
    bool showOldEvents,
    bool showDrawing,
    PendingNextAppointment? pendingNextAppointment,
    int viewMode,
  ) {
    final windowStart = viewMode == ScheduleDrawing.VIEW_MODE_2DAY
        ? ScheduleLayoutUtils.get2DayWindowStart(controller.selectedDate)
        : ScheduleLayoutUtils.get3DayWindowStart(controller.selectedDate);

    final windowSize = viewMode == ScheduleDrawing.VIEW_MODE_2DAY ? 2 : 3;
    final dates = List.generate(
      windowSize,
      (index) => windowStart.add(Duration(days: index)),
    );

    return ScheduleBody(
      dates: dates,
      events: events,
      showOldEvents: showOldEvents,
      showDrawing: showDrawing,
      isDrawingMode: controller.isDrawingMode,
      canvasKey: controller.getCanvasKeyForCurrentPage(),
      currentDrawing: controller.drawingService?.currentDrawing,
      transformationController: controller.transformationController,
      getEventTypeColor: (context, eventType) =>
          controller.eventService?.getEventTypeColor(eventType) ?? Colors.grey,
      onEditEvent: (event) => controller.eventService?.editEvent(event),
      onShowEventContextMenu: (event, position) =>
          controller.eventService?.showEventContextMenu(event, position),
      onCreateEvent: (startTime) {
        controller.eventService?.createEvent(
          startTime: startTime,
          name: pendingNextAppointment?.name,
          recordNumber: pendingNextAppointment?.recordNumber,
          phone: pendingNextAppointment?.phone,
          eventTypes: pendingNextAppointment?.eventTypes,
        );
        if (pendingNextAppointment != null) {
          context.read<ScheduleCubit>().clearPendingNextAppointment();
        }
      },
      onEventDrop: (event, newStartTime) => controller.eventService
          ?.handleEventDrop(event, newStartTime, context),
      onCloseEventMenu: () => controller.eventService?.closeEventMenu(),
      onDrawingStrokesChanged: () {
        controller.markNeedsBuild();
        controller.scheduleSaveDrawing();
      },
      selectedEventForMenu: controller.eventService?.selectedEventForMenu,
      menuPosition: controller.eventService?.menuPosition,
      onChangeType: controller.eventService?.selectedEventForMenu != null
          ? () => controller.eventService?.handleMenuAction(
              'changeType',
              controller.eventService!.selectedEventForMenu!,
              context,
            )
          : null,
      onChangeTime: controller.eventService?.selectedEventForMenu != null
          ? () => controller.eventService?.handleMenuAction(
              'changeTime',
              controller.eventService!.selectedEventForMenu!,
              context,
            )
          : null,
      onScheduleNextAppointment:
          controller.eventService?.selectedEventForMenu != null
          ? () => controller.eventService?.scheduleNextAppointment(
              controller.eventService!.selectedEventForMenu!,
              context,
            )
          : null,
      onRemove: controller.eventService?.selectedEventForMenu != null
          ? () => controller.eventService?.handleMenuAction(
              'remove',
              controller.eventService!.selectedEventForMenu!,
              context,
            )
          : null,
      onDelete: controller.eventService?.selectedEventForMenu != null
          ? () => controller.eventService?.handleMenuAction(
              'delete',
              controller.eventService!.selectedEventForMenu!,
              context,
            )
          : null,
      onCheckedChanged: controller.eventService?.selectedEventForMenu != null
          ? (isChecked) => controller.eventService?.toggleEventChecked(
              controller.eventService!.selectedEventForMenu!,
              isChecked,
            )
          : null,
    );
  }
}
