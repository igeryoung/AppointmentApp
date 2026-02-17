import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../cubits/schedule_cubit.dart';
import '../../cubits/schedule_state.dart';
import '../../l10n/app_localizations.dart';
import '../../models/book.dart';
import '../../models/event.dart';
import '../../models/schedule_drawing.dart';
import '../../services/content_service.dart';
import '../../services/database_service_interface.dart';
import '../../services/time_service.dart';
import '../../utils/schedule/schedule_layout_utils.dart';
import 'services/event_management_service.dart';
import 'services/schedule_connectivity_service.dart';
import 'services/schedule_date_service.dart';
import 'services/schedule_drawing_service.dart';
import '../book_list/utils/snackbar_utils.dart';
import '../../widgets/handwriting_canvas.dart';

/// Controller that encapsulates ScheduleScreen lifecycle, state, and services.
class ScheduleController extends ChangeNotifier {
  ScheduleController({
    required this.book,
    required IDatabaseService dbService,
    required this.contextProvider,
  }) : _dbService = dbService {
    assert(
      book.uuid.isNotEmpty,
      'Book must have a valid UUID to open ScheduleScreen',
    );
  }

  final Book book;
  final IDatabaseService _dbService;
  final BuildContext Function() contextProvider;

  final TransformationController transformationController =
      TransformationController();

  DateTime _selectedDate = TimeService.instance.now();
  DateTime get selectedDate => _selectedDate;
  int _viewMode = ScheduleDrawing.VIEW_MODE_2DAY;
  int get viewMode => _viewMode;

  DateTime? _previousSelectedDate;
  DateTime? get previousSelectedDate => _previousSelectedDate;
  set previousSelectedDate(DateTime? value) {
    _previousSelectedDate = value;
    notifyListeners();
  }

  DateTime _lastActiveDate = TimeService.instance.now();
  DateTime get lastActiveDate => _lastActiveDate;

  bool _isDrawingMode = false;
  bool get isDrawingMode => _isDrawingMode;

  bool _isFabMenuVisible = false;
  bool get isFabMenuVisible => _isFabMenuVisible;

  bool _isNavigating = false;
  bool get isNavigating => _isNavigating;

  int _currentPreloadGeneration = 0;
  int get currentPreloadGeneration => _currentPreloadGeneration;

  int _navigationGeneration = 0;
  int get navigationGeneration => _navigationGeneration;

  ContentService? _contentService;
  ContentService? get contentService => _contentService;

  ScheduleDrawingService? _drawingService;
  ScheduleDrawingService? get drawingService => _drawingService;

  ScheduleDateService? _dateService;
  ScheduleDateService? get dateService => _dateService;

  ScheduleConnectivityService? _connectivityService;
  ScheduleConnectivityService? get connectivityService => _connectivityService;

  EventManagementService? _eventService;
  EventManagementService? get eventService => _eventService;

  String get _bookUuid => book.uuid;

  /// Initialize services and load initial data.
  Future<void> initialize(BuildContext context) async {
    _drawingService = ScheduleDrawingService(
      bookUuid: _bookUuid,
      contentService: _contentService,
      onDrawingChanged: () => notifyListeners(),
    );

    _dateService = ScheduleDateService(
      initialDate: _selectedDate,
      onDateChanged: (selectedDate, lastActiveDate) {
        _navigationGeneration++;
        _selectedDate = selectedDate;
        _lastActiveDate = lastActiveDate;
        notifyListeners();
      },
      onSaveDrawing: () async => await saveDrawing(context),
      onLoadDrawing: () async => await loadDrawing(),
      onUpdateCubit: (date) => context.read<ScheduleCubit>().selectDate(date),
      onShowNotification: (messageKey) {
        if (messageKey == 'dateChangedToToday') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.dateChangedToToday),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      isMounted: () => context.mounted,
      isInDrawingMode: () => _isDrawingMode,
      onCancelPendingSave: () => _drawingService?.cancelPendingSave(),
    );

    _dateService!.onNavigatingStateChanged = (isNavigating) {
      _isNavigating = isNavigating;
      notifyListeners();
    };
    _dateService!.onExitDrawingMode = () {
      _isDrawingMode = false;
      notifyListeners();
    };

    _connectivityService = ScheduleConnectivityService(
      dbService: _dbService,
      bookUuid: _bookUuid,
      onStateChanged: (isOffline, isSyncing) => notifyListeners(),
      onUpdateCubitOfflineStatus: (isOffline) {
        context.read<ScheduleCubit>().setOfflineStatus(isOffline);
      },
      onShowSnackbar:
          (
            message, {
            backgroundColor,
            durationSeconds,
            action,
            detailTitle,
            detailMessage,
          }) {
            if (!context.mounted) return;

            if (detailTitle != null && detailMessage != null) {
              if (backgroundColor == Colors.orange) {
                SnackBarUtils.showWarningWithDetails(
                  context: context,
                  message: message,
                  detailTitle: detailTitle,
                  detailMessage: detailMessage,
                );
              } else if (backgroundColor == Colors.red) {
                SnackBarUtils.showErrorWithDetails(
                  context: context,
                  message: message,
                  detailTitle: detailTitle,
                  detailMessage: detailMessage,
                );
              } else if (backgroundColor == Colors.green) {
                SnackBarUtils.showSuccessWithDetails(
                  context: context,
                  message: message,
                  detailTitle: detailTitle,
                  detailMessage: detailMessage,
                );
              } else {
                SnackBarUtils.showInfoWithDetails(
                  context: context,
                  message: message,
                  detailTitle: detailTitle,
                  detailMessage: detailMessage,
                );
              }
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(message),
                  backgroundColor: backgroundColor,
                  duration: Duration(seconds: durationSeconds ?? 2),
                  action: action,
                ),
              );
            }
          },
      isMounted: () => context.mounted,
      onUpdateDrawingServiceContentService: (contentService) {
        if (_drawingService != null) {
          _drawingService!.contentService = contentService;
        }
      },
    );

    _eventService = EventManagementService(
      dbService: _dbService,
      bookUuid: _bookUuid,
      onMenuStateChanged: (selectedEvent, position) => notifyListeners(),
      onNavigate: (screen) async {
        return await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (context) => screen),
        );
      },
      onReloadEvents: () => context.read<ScheduleCubit>().loadEvents(),
      onUpdateEvent: (event) =>
          context.read<ScheduleCubit>().updateEvent(event),
      onDeleteEvent: (eventId, reason) async {
        final updatedEvent = await context.read<ScheduleCubit>().deleteEvent(
          eventId,
          reason: reason,
        );
        return updatedEvent;
      },
      onHardDeleteEvent: (eventId) async {
        final updatedEvent = await context
            .read<ScheduleCubit>()
            .hardDeleteEvent(eventId);
        return updatedEvent;
      },
      onChangeEventTime: (event, startTime, endTime, reason) async {
        await context.read<ScheduleCubit>().changeEventTime(
          event,
          startTime,
          endTime,
          reason,
        );
      },
      onShowSnackbar: (message, {backgroundColor, durationSeconds}) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: backgroundColor,
            duration: Duration(seconds: durationSeconds ?? 2),
          ),
        );
      },
      isMounted: () => context.mounted,
      getLocalizedString: (getter) => getter(AppLocalizations.of(context)!),
      onSyncEvent: (event) async {
        await _connectivityService?.syncEventToServer(event);
      },
      onSetPendingNextAppointment: (pending) =>
          context.read<ScheduleCubit>().setPendingNextAppointment(pending),
      dateService: _dateService!,
    );

    _dateService?.startPeriodicCheck();
    await _connectivityService?.initialize();
    _contentService = _connectivityService?.contentService;
    _connectivityService?.setupConnectivityMonitoring();

    final currentState = context.read<ScheduleCubit>().state;
    if (currentState is ScheduleLoaded) {
      _viewMode = currentState.viewMode;
      _dateService?.setViewMode(_viewMode);
    }

    await _drawingService?.loadDrawing(_selectedDate, viewMode: _viewMode);
  }

  @override
  void dispose() {
    _dateService?.dispose();
    _connectivityService?.dispose();
    _drawingService?.dispose();
    transformationController.dispose();
    super.dispose();
  }

  /// Lifecycle handler for app resume/pause.
  Future<void> handleLifecycle(
    AppLifecycleState state,
    BuildContext context,
  ) async {
    if (state == AppLifecycleState.resumed) {
      _dateService?.checkAndHandleDateChange();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_isDrawingMode) {
        await saveDrawing(context);
      }
    }
  }

  /// Generate unique page identifier for current view and date.
  String getPageId() => _drawingService!.getPageId(_selectedDate, _viewMode);

  /// Canvas key for current page.
  GlobalKey<HandwritingCanvasState> getCanvasKeyForCurrentPage() =>
      _drawingService!.getCanvasKey(_selectedDate, _viewMode);

  Future<void> loadDrawing() async {
    await _drawingService?.loadDrawing(_selectedDate, viewMode: _viewMode);
  }

  Future<void> preloadNotesInBackground(
    BuildContext context,
    List<Event> events,
    int generation,
  ) async {
    if (events.isEmpty) return;
    if (_contentService == null) return;

    final eventIds = events
        .where((e) => e.id != null)
        .map((e) => e.id!)
        .toList();
    if (eventIds.isEmpty) return;

    final preloadStartTime = DateTime.now();
    try {
      await _contentService!.preloadNotes(
        eventIds,
        generation: generation,
        isCancelled: () => generation != _currentPreloadGeneration,
        onProgress: (loaded, total) {},
      );
      final _ = DateTime.now().difference(preloadStartTime);
    } catch (e) {
      final _ = DateTime.now().difference(preloadStartTime);
    }
  }

  void scheduleSaveDrawing() =>
      _drawingService?.scheduleSave(_selectedDate, _viewMode);

  Future<void> saveDrawing(BuildContext context) async {
    try {
      await _drawingService?.saveDrawing(_selectedDate, viewMode: _viewMode);
      final savedDrawing = _drawingService?.currentDrawing;
      if (context.mounted && savedDrawing != null) {
        context.read<ScheduleCubit>().saveDrawing(savedDrawing);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.errorSavingDrawing(e.toString()),
            ),
          ),
        );
      }
    }
  }

  /// Force a rebuild for view consumers when no state fields change.
  void markNeedsBuild() => notifyListeners();

  Future<void> toggleDrawingMode(BuildContext context) async {
    if (_isDrawingMode) {
      await saveDrawing(context);
      _isDrawingMode = false;
      notifyListeners();
    } else {
      _isDrawingMode = true;
      notifyListeners();
      await loadDrawing();
    }
  }

  void toggleFabMenu() {
    _isFabMenuVisible = !_isFabMenuVisible;
    notifyListeners();
  }

  void changeDateTo(DateTime newDate) {
    _selectedDate = newDate;
    _lastActiveDate = newDate;
    notifyListeners();
  }

  void setViewMode(int viewMode) {
    if (_viewMode == viewMode) {
      _dateService?.setViewMode(viewMode);
      return;
    }

    _viewMode = viewMode;
    _dateService?.setViewMode(viewMode);
    notifyListeners();
  }

  void panToCurrentTime() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      transformationController.value = Matrix4.identity();
    });
  }

  /// Handle state change when bloc loads events and date windows shift.
  void handleLoadedState(ScheduleLoaded state, BuildContext context) {
    _currentPreloadGeneration++;
    final preloadGeneration = _currentPreloadGeneration;
    preloadNotesInBackground(context, state.events, preloadGeneration);

    final didViewModeChange = _viewMode != state.viewMode;
    if (didViewModeChange) {
      _viewMode = state.viewMode;
    }
    _dateService?.setViewMode(_viewMode);

    if (didViewModeChange) {
      _previousSelectedDate = state.selectedDate;
      loadDrawing();
      return;
    }

    final currentWindow = _previousSelectedDate != null
        ? _getWindowStart(_previousSelectedDate!, _viewMode)
        : null;
    final newWindow = _getWindowStart(state.selectedDate, _viewMode);
    final localWindow = _getWindowStart(_selectedDate, _viewMode);

    if (currentWindow != newWindow) {
      if (newWindow == localWindow) {
        _previousSelectedDate = state.selectedDate;
      } else {
        _previousSelectedDate = state.selectedDate;
        if (_selectedDate != state.selectedDate) {
          _selectedDate = state.selectedDate;
          notifyListeners();
        }
        loadDrawing();
      }
    }
  }

  /// Increment and return the current preload generation counter.
  int bumpPreloadGeneration() {
    _currentPreloadGeneration++;
    return _currentPreloadGeneration;
  }

  DateTime _getWindowStart(DateTime date, int viewMode) {
    return ScheduleLayoutUtils.getEffectiveDate(date, viewMode: viewMode);
  }
}
