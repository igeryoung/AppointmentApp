import 'package:flutter/foundation.dart';
import '../../../models/note.dart';
import '../../../services/content_service.dart';


/// Thin adapter for ContentService note sync operations
class NoteSyncAdapter {
  final ContentService _contentService;

  NoteSyncAdapter(this._contentService);

  /// Get cached note from local storage
  Future<Note?> getCachedNote(String eventId) async {
    return await _contentService.getCachedNote(eventId);
  }

  /// Get note with cache-first strategy
  Future<Note?> getNote(String eventId, {bool forceRefresh = false}) async {
    return await _contentService.getNote(eventId, forceRefresh: forceRefresh);
  }

  /// Save note locally (offline-first)
  Future<void> saveNote(String eventId, Note note) async {
    await _contentService.saveNote(eventId, note);
  }

  /// Sync note to server (background operation)
  Future<void> syncNote(String eventId) async {
    await _contentService.syncNote(eventId);
  }
}
