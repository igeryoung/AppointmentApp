import 'dart:async';
import 'package:flutter/material.dart';

import '../../../models/schedule_drawing.dart';
import '../../../services/database_service_interface.dart';
import '../../../services/content_service.dart';
import '../../../services/time_service.dart';
import '../../../utils/schedule/schedule_layout_utils.dart';
import '../../../widgets/handwriting_canvas.dart';

/// Service for managing schedule drawing operations
///
/// Handles:
/// - Canvas key management for multi-page drawings
/// - Loading drawings (cache-first with server fallback)
/// - Saving drawings with debouncing and race condition prevention
/// - Version tracking for optimistic locking
class ScheduleDrawingService {
  final IDatabaseService _dbService;
  ContentService? _contentService;
  final int bookId;
  final VoidCallback onDrawingChanged;

  // Canvas key management - one key per 3-day window
  final Map<String, GlobalKey<HandwritingCanvasState>> _canvasKeys = {};

  // Current drawing state
  ScheduleDrawing? _currentDrawing;

  // Save debouncing and race condition prevention
  Timer? _saveDebounceTimer;
  bool _isSaving = false;
  int _lastSavedCanvasVersion = 0;

  ScheduleDrawingService({
    required IDatabaseService dbService,
    required this.bookId,
    required this.onDrawingChanged,
    ContentService? contentService,
  })  : _dbService = dbService,
        _contentService = contentService;

  /// Get the current drawing
  ScheduleDrawing? get currentDrawing => _currentDrawing;

  /// Update ContentService (for late initialization)
  set contentService(ContentService? service) {
    _contentService = service;
  }

  /// Generate page ID for a given date (3-day window identifier)
  String getPageId(DateTime selectedDate) {
    final normalizedDate = ScheduleLayoutUtils.get3DayWindowStart(selectedDate);
    return '3day_${normalizedDate.millisecondsSinceEpoch}';
  }

  /// Get or create canvas key for the current page
  GlobalKey<HandwritingCanvasState> getCanvasKey(DateTime selectedDate) {
    final pageId = getPageId(selectedDate);
    if (!_canvasKeys.containsKey(pageId)) {
      _canvasKeys[pageId] = GlobalKey<HandwritingCanvasState>();
    }
    return _canvasKeys[pageId]!;
  }

  /// Load drawing for the selected date (cache-first with server fallback)
  Future<void> loadDrawing(DateTime selectedDate) async {
    try {
      // Reset current drawing to avoid carrying old IDs
      _currentDrawing = null;
      onDrawingChanged();

      // Use effective date to ensure consistency with UI rendering
      final effectiveDate = ScheduleLayoutUtils.getEffectiveDate(selectedDate);

      // Use ContentService for cache-first strategy with server fallback
      ScheduleDrawing? drawing;
      if (_contentService != null) {
        debugPrint('📖 Loading drawing via ContentService (cache-first with server fallback)...');
        drawing = await _contentService!.getDrawing(
          bookId: bookId,
          date: effectiveDate,
          viewMode: ScheduleDrawing.VIEW_MODE_3DAY,
          forceRefresh: false,
        );
      } else {
        // Fallback to direct database access
        debugPrint('⚠️ ContentService not available, loading drawing from cache only');
        drawing = await _dbService.getCachedDrawing(
          bookId,
          effectiveDate,
          ScheduleDrawing.VIEW_MODE_3DAY,
        );
      }

      _currentDrawing = drawing;
      onDrawingChanged();

      // Load strokes into canvas (use post-frame callback)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadStrokesIntoCanvas(selectedDate, drawing);
      });
    } catch (e) {
      debugPrint('❌ Error loading drawing: $e');
      _currentDrawing = null;
      onDrawingChanged();
    }
  }

  /// Load strokes from drawing into canvas
  void _loadStrokesIntoCanvas(DateTime selectedDate, ScheduleDrawing? drawing) {
    final canvasKey = getCanvasKey(selectedDate);
    final pageId = getPageId(selectedDate);
    final effectiveDate = ScheduleLayoutUtils.getEffectiveDate(selectedDate);

    if (drawing != null && drawing.strokes.isNotEmpty) {
      debugPrint('📖 Loading ${drawing.strokes.length} strokes for page $pageId (effectiveDate: $effectiveDate)');
      canvasKey.currentState?.loadStrokes(drawing.strokes);
    } else {
      debugPrint('📖 Clearing canvas for empty page $pageId (effectiveDate: $effectiveDate)');
      canvasKey.currentState?.clear();
    }
  }

  /// Schedule a debounced save (500ms delay)
  void scheduleSave(DateTime selectedDate) {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      saveDrawing(selectedDate);
    });
    debugPrint('⏱️ Scheduled debounced save (500ms)');
  }

  /// Cancel pending debounced save
  void cancelPendingSave() {
    _saveDebounceTimer?.cancel();
  }

  /// Save drawing with race condition prevention
  Future<void> saveDrawing(DateTime selectedDate) async {
    // Prevent concurrent saves
    if (_isSaving) {
      debugPrint('⚠️ Save already in progress, skipping...');
      return;
    }

    final canvasKey = getCanvasKey(selectedDate);
    final canvasState = canvasKey.currentState;
    if (canvasState == null) {
      debugPrint('⚠️ Cannot save: canvas state is null');
      return;
    }

    // Check if canvas version has changed since last save
    final currentCanvasVersion = canvasState.canvasVersion;
    if (currentCanvasVersion == _lastSavedCanvasVersion) {
      debugPrint('⏩ Canvas unchanged (version: $currentCanvasVersion), skipping save');
      return;
    }

    _isSaving = true;
    try {
      final strokes = canvasState.getStrokes();
      final now = TimeService.instance.now();
      final effectiveDate = ScheduleLayoutUtils.getEffectiveDate(selectedDate);
      final pageId = getPageId(selectedDate);

      // Only use existing ID, createdAt, and version if it matches the current page
      int? drawingId;
      DateTime? createdAt;
      int version = 1;
      if (_currentDrawing != null &&
          _currentDrawing!.bookId == bookId &&
          _currentDrawing!.viewMode == ScheduleDrawing.VIEW_MODE_3DAY &&
          _currentDrawing!.date.year == effectiveDate.year &&
          _currentDrawing!.date.month == effectiveDate.month &&
          _currentDrawing!.date.day == effectiveDate.day) {
        drawingId = _currentDrawing!.id;
        createdAt = _currentDrawing!.createdAt;
        version = _currentDrawing!.version;
      }

      final drawing = ScheduleDrawing(
        id: drawingId,
        bookId: bookId,
        date: effectiveDate,
        viewMode: ScheduleDrawing.VIEW_MODE_3DAY,
        strokes: strokes,
        version: version,
        createdAt: createdAt ?? now,
        updatedAt: now,
      );

      debugPrint('💾 Saving ${strokes.length} strokes for page $pageId (effectiveDate: $effectiveDate, id: $drawingId, version: $version)');

      // Use ContentService or fallback to database
      if (_contentService != null) {
        debugPrint('💾 Saving drawing via ContentService (syncs to server + cache)...');
        await _contentService!.saveDrawing(drawing);

        // Race condition check
        final currentStateAfterSave = canvasKey.currentState;
        if (currentStateAfterSave != null &&
            currentStateAfterSave.canvasVersion != currentCanvasVersion) {
          debugPrint('⚠️ Canvas changed during save (v$currentCanvasVersion → v${currentStateAfterSave.canvasVersion}), skipping state update');
          return;
        }

        // Update current drawing state
        final savedDrawing = await _dbService.getCachedDrawing(
          bookId,
          effectiveDate,
          ScheduleDrawing.VIEW_MODE_3DAY,
        );
        _currentDrawing = savedDrawing ?? drawing;
      } else {
        debugPrint('⚠️ ContentService not available, saving to cache only');
        final savedDrawing = await _dbService.saveCachedDrawing(drawing);

        // Race condition check
        final currentStateAfterSave = canvasKey.currentState;
        if (currentStateAfterSave != null &&
            currentStateAfterSave.canvasVersion != currentCanvasVersion) {
          debugPrint('⚠️ Canvas changed during save (v$currentCanvasVersion → v${currentStateAfterSave.canvasVersion}), skipping state update');
          return;
        }

        _currentDrawing = savedDrawing;
      }

      debugPrint('✅ Save successful, id: ${_currentDrawing?.id}');
      _lastSavedCanvasVersion = currentCanvasVersion;
      onDrawingChanged();
    } catch (e) {
      debugPrint('❌ Error saving drawing: $e');
      rethrow; // Let caller handle the error
    } finally {
      _isSaving = false;
    }
  }

  /// Dispose resources
  void dispose() {
    _saveDebounceTimer?.cancel();
  }
}
