import 'dart:async';
import 'package:flutter/material.dart';

import '../../../models/schedule_drawing.dart';
import '../../../services/content_service.dart';
import '../../../services/time_service.dart';
import '../../../utils/schedule/schedule_layout_utils.dart';
import '../../../widgets/handwriting_canvas.dart';

/// Service for managing schedule drawing operations
///
/// Handles:
/// - Canvas key management for multi-page drawings
/// - Loading drawings from server
/// - Saving drawings with debouncing and race condition prevention
/// - Version tracking for optimistic locking
class ScheduleDrawingService {
  ContentService? _contentService;
  final String bookUuid;
  final VoidCallback onDrawingChanged;

  // Canvas key management - one key per effective schedule window
  final Map<String, GlobalKey<HandwritingCanvasState>> _canvasKeys = {};

  // Current drawing state
  ScheduleDrawing? _currentDrawing;

  // Save debouncing and race condition prevention
  Timer? _saveDebounceTimer;
  bool _isSaving = false;
  int _lastSavedCanvasVersion = 0;

  // RACE CONDITION FIX: Drawing load generation counter
  int _drawingLoadGeneration = 0;

  ScheduleDrawingService({
    required this.bookUuid,
    required this.onDrawingChanged,
    ContentService? contentService,
  }) : _contentService = contentService;

  /// Get the current drawing
  ScheduleDrawing? get currentDrawing => _currentDrawing;

  /// Update ContentService (for late initialization)
  set contentService(ContentService? service) {
    _contentService = service;
  }

  /// Generate page ID for a given date and view mode.
  String getPageId(DateTime selectedDate, int viewMode) {
    final normalizedDate = ScheduleLayoutUtils.getEffectiveDate(
      selectedDate,
      viewMode: viewMode,
    );
    return 'vm_${viewMode}_${normalizedDate.millisecondsSinceEpoch}';
  }

  /// Get or create canvas key for the current page
  GlobalKey<HandwritingCanvasState> getCanvasKey(
    DateTime selectedDate,
    int viewMode,
  ) {
    final pageId = getPageId(selectedDate, viewMode);
    if (!_canvasKeys.containsKey(pageId)) {
      _canvasKeys[pageId] = GlobalKey<HandwritingCanvasState>();
    }
    return _canvasKeys[pageId]!;
  }

  /// Load drawing for the selected date (cache-first with server fallback)
  Future<void> loadDrawing(
    DateTime selectedDate, {
    required int viewMode,
  }) async {
    // RACE CONDITION FIX: Increment generation counter
    _drawingLoadGeneration++;
    final loadGeneration = _drawingLoadGeneration;

    try {
      // Reset current drawing to avoid carrying old IDs
      _currentDrawing = null;
      onDrawingChanged();

      // Use effective date to ensure consistency with UI rendering
      final effectiveDate = ScheduleLayoutUtils.getEffectiveDate(
        selectedDate,
        viewMode: viewMode,
      );

      // Use ContentService (server-only)
      ScheduleDrawing? drawing;
      if (_contentService != null) {
        drawing = await _contentService!.getDrawing(
          bookUuid: bookUuid,
          date: effectiveDate,
          viewMode: viewMode,
          forceRefresh: false,
        );
      } else {
        throw Exception('ContentService is not initialized');
      }

      // RACE CONDITION FIX: Check if this load is still valid
      if (loadGeneration != _drawingLoadGeneration) {
        return;
      }

      _currentDrawing = drawing;
      onDrawingChanged();

      // Load strokes into canvas (use post-frame callback)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // RACE CONDITION FIX: Check again before loading into canvas
        if (loadGeneration == _drawingLoadGeneration) {
          _loadStrokesIntoCanvas(selectedDate, drawing, viewMode: viewMode);
        } else {}
      });
    } catch (e) {
      // Only update state if this load is still current
      if (loadGeneration == _drawingLoadGeneration) {
        _currentDrawing = null;
        onDrawingChanged();
      }
    }
  }

  /// Load strokes from drawing into canvas
  void _loadStrokesIntoCanvas(
    DateTime selectedDate,
    ScheduleDrawing? drawing, {
    required int viewMode,
  }) {
    final canvasKey = getCanvasKey(selectedDate, viewMode);

    if (drawing != null && drawing.strokes.isNotEmpty) {
      canvasKey.currentState?.loadStrokes(drawing.strokes);
    } else {
      canvasKey.currentState?.clear();
    }
  }

  /// Schedule a debounced save (500ms delay)
  void scheduleSave(DateTime selectedDate, int viewMode) {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      saveDrawing(selectedDate, viewMode: viewMode);
    });
  }

  /// Cancel pending debounced save
  void cancelPendingSave() {
    _saveDebounceTimer?.cancel();
  }

  /// Save drawing with race condition prevention
  Future<void> saveDrawing(
    DateTime selectedDate, {
    required int viewMode,
  }) async {
    // Prevent concurrent saves
    if (_isSaving) {
      return;
    }

    // RACE CONDITION FIX: Capture date at save start for validation
    final dateAtSaveStart = selectedDate;
    final effectiveDateAtStart = ScheduleLayoutUtils.getEffectiveDate(
      dateAtSaveStart,
      viewMode: viewMode,
    );

    final canvasKey = getCanvasKey(selectedDate, viewMode);
    final canvasState = canvasKey.currentState;
    if (canvasState == null) {
      return;
    }

    // Check if canvas version has changed since last save
    final currentCanvasVersion = canvasState.canvasVersion;
    if (currentCanvasVersion == _lastSavedCanvasVersion) {
      return;
    }

    _isSaving = true;
    try {
      final strokes = canvasState.getStrokes();
      final now = TimeService.instance.now();
      final effectiveDate = ScheduleLayoutUtils.getEffectiveDate(
        selectedDate,
        viewMode: viewMode,
      );

      // Only use existing ID, createdAt, and version if it matches the current page
      int? drawingId;
      DateTime? createdAt;
      int version = 1;
      if (_currentDrawing != null &&
          _currentDrawing!.bookUuid == bookUuid &&
          _currentDrawing!.viewMode == viewMode &&
          _currentDrawing!.date.year == effectiveDate.year &&
          _currentDrawing!.date.month == effectiveDate.month &&
          _currentDrawing!.date.day == effectiveDate.day) {
        drawingId = _currentDrawing!.id;
        createdAt = _currentDrawing!.createdAt;
        version = _currentDrawing!.version;
      }

      final drawing = ScheduleDrawing(
        id: drawingId,
        bookUuid: bookUuid,
        date: effectiveDate,
        viewMode: viewMode,
        strokes: strokes,
        version: version,
        createdAt: createdAt ?? now,
        updatedAt: now,
      );

      // Use ContentService (server-only)
      if (_contentService != null) {
        await _contentService!.saveDrawing(drawing);

        // RACE CONDITION FIX: Verify date hasn't changed during save
        final effectiveDateAfterSave = ScheduleLayoutUtils.getEffectiveDate(
          selectedDate,
          viewMode: viewMode,
        );
        if (effectiveDateAtStart != effectiveDateAfterSave) {
          return;
        }

        // Race condition check - canvas version
        final currentStateAfterSave = canvasKey.currentState;
        if (currentStateAfterSave != null &&
            currentStateAfterSave.canvasVersion != currentCanvasVersion) {
          return;
        }

        _currentDrawing = drawing;
      } else {
        throw Exception('ContentService is not initialized');
      }

      _lastSavedCanvasVersion = currentCanvasVersion;
      onDrawingChanged();
    } catch (e) {
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
