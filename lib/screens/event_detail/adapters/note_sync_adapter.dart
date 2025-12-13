import '../../../models/note.dart';
import '../../../services/content_service.dart';


/// Adapter for server-only note operations
class NoteSyncAdapter {
  final ContentService _contentService;

  NoteSyncAdapter(this._contentService);

  /// Get note from server
  Future<Note?> getNote(String eventId, {bool forceRefresh = false}) async {
    return await _contentService.getNote(eventId, forceRefresh: forceRefresh);
  }

  /// Save note to server
  Future<void> saveNote(String eventId, Note note) async {
    await _contentService.saveNote(eventId, note);
  }
}
