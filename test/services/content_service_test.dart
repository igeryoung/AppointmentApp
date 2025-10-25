import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/models/book.dart';
import 'package:schedule_note_app/models/event.dart';
import 'package:schedule_note_app/models/note.dart';
import 'package:schedule_note_app/models/schedule_drawing.dart';
import 'package:schedule_note_app/services/api_client.dart';
import 'package:schedule_note_app/services/cache_manager.dart';
import 'package:schedule_note_app/services/content_service.dart';
import 'package:schedule_note_app/services/prd_database_service.dart';

void main() {
  group('ContentService Tests', () {
    late ContentService contentService;
    late _MockApiClient mockApiClient;
    late _MockCacheManager mockCacheManager;
    late _MockDatabase mockDb;

    setUp(() {
      mockApiClient = _MockApiClient();
      mockCacheManager = _MockCacheManager();
      mockDb = _MockDatabase();
      contentService = ContentService(mockApiClient, mockCacheManager, mockDb);
    });

    group('Notes Operations', () {
      test('getNote - cache hit returns cached note', () async {
        // Arrange
        final cachedNote = Note(
          eventId: 1,
          strokes: const [Stroke(points: [StrokePoint(10, 10)])],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        mockCacheManager.mockNotes[1] = cachedNote;

        // Act
        final result = await contentService.getNote(1);

        // Assert
        expect(result, isNotNull);
        expect(result!.eventId, 1);
        expect(result.strokes.length, 1);
        expect(mockApiClient.fetchNoteCalled, false,
            reason: 'Should not call API on cache hit');
      });

      test('getNote - cache miss fetches from server and caches', () async {
        // Arrange
        mockDb.mockEvent = Event(
          id: 1,
          bookId: 10,
          name: 'Test Event',
          recordNumber: 'REC001',
          eventType: 'appointment',
          startTime: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        mockDb.mockCredentials = const DeviceCredentials(
          deviceId: 'device123',
          deviceToken: 'token123',
        );
        mockApiClient.mockNoteResponse = {
          'event_id': 1,
          'strokes_data': '[{"points":[{"dx":10.0,"dy":10.0,"pressure":1.0}],"stroke_width":2.0,"color":4278190080}]',
          'created_at': 1234567890,
          'updated_at': 1234567890,
        };

        // Act
        final result = await contentService.getNote(1);

        // Assert
        expect(result, isNotNull);
        expect(result!.eventId, 1);
        expect(mockApiClient.fetchNoteCalled, true);
        expect(mockCacheManager.savedNotes.containsKey(1), true,
            reason: 'Should cache the fetched note');
      });

      test('getNote - network error returns cached note (fallback)', () async {
        // Arrange
        final cachedNote = Note(
          eventId: 1,
          strokes: const [Stroke(points: [StrokePoint(20, 20)])],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        mockCacheManager.mockNotes[1] = cachedNote;
        mockDb.mockEvent = Event(
          id: 1,
          bookId: 10,
          name: 'Test Event',
          recordNumber: 'REC001',
          eventType: 'appointment',
          startTime: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        mockDb.mockCredentials = const DeviceCredentials(
          deviceId: 'device123',
          deviceToken: 'token123',
        );
        mockApiClient.shouldThrowError = true;

        // Act
        final result = await contentService.getNote(1);

        // Assert
        expect(result, isNotNull);
        expect(result!.strokes.first.points.first.dx, 20.0,
            reason: 'Should return cached note on network error');
      });

      test('getNote - no cache and network error returns null', () async {
        // Arrange
        mockDb.mockEvent = Event(
          id: 1,
          bookId: 10,
          name: 'Test Event',
          recordNumber: 'REC001',
          eventType: 'appointment',
          startTime: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        mockDb.mockCredentials = const DeviceCredentials(
          deviceId: 'device123',
          deviceToken: 'token123',
        );
        mockApiClient.shouldThrowError = true;

        // Act
        final result = await contentService.getNote(1);

        // Assert
        expect(result, isNull);
      });

      test('getNote - forceRefresh bypasses cache', () async {
        // Arrange
        final cachedNote = Note(
          eventId: 1,
          strokes: const [Stroke(points: [StrokePoint(10, 10)])],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        mockCacheManager.mockNotes[1] = cachedNote;
        mockDb.mockEvent = Event(
          id: 1,
          bookId: 10,
          name: 'Test Event',
          recordNumber: 'REC001',
          eventType: 'appointment',
          startTime: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        mockDb.mockCredentials = const DeviceCredentials(
          deviceId: 'device123',
          deviceToken: 'token123',
        );
        mockApiClient.mockNoteResponse = {
          'event_id': 1,
          'strokes_data': '[{"points":[{"dx":99.0,"dy":99.0,"pressure":1.0}],"stroke_width":2.0,"color":4278190080}]',
          'created_at': 1234567890,
          'updated_at': 1234567890,
        };

        // Act
        final result = await contentService.getNote(1, forceRefresh: true);

        // Assert
        expect(result, isNotNull);
        expect(result!.strokes.first.points.first.dx, 99.0,
            reason: 'Should fetch from server, not cache');
        expect(mockApiClient.fetchNoteCalled, true);
      });

      test('saveNote - saves to server and cache', () async {
        // Arrange
        mockDb.mockEvent = Event(
          id: 1,
          bookId: 10,
          name: 'Test Event',
          recordNumber: 'REC001',
          eventType: 'appointment',
          startTime: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        mockDb.mockCredentials = const DeviceCredentials(
          deviceId: 'device123',
          deviceToken: 'token123',
        );
        final note = Note(
          eventId: 1,
          strokes: const [Stroke(points: [StrokePoint(50, 50)])],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        // Act
        await contentService.saveNote(1, note);

        // Assert
        expect(mockApiClient.saveNoteCalled, true);
        expect(mockCacheManager.savedNotes.containsKey(1), true);
      });

      test('saveNote - server fails, still saves to cache', () async {
        // Arrange
        mockDb.mockEvent = Event(
          id: 1,
          bookId: 10,
          name: 'Test Event',
          recordNumber: 'REC001',
          eventType: 'appointment',
          startTime: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        mockDb.mockCredentials = const DeviceCredentials(
          deviceId: 'device123',
          deviceToken: 'token123',
        );
        mockApiClient.shouldThrowError = true;
        final note = Note(
          eventId: 1,
          strokes: const [Stroke(points: [StrokePoint(50, 50)])],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        // Act
        await contentService.saveNote(1, note);

        // Assert
        expect(mockCacheManager.savedNotes.containsKey(1), true,
            reason: 'Should save to cache even if server fails');
      });

      test('deleteNote - deletes from server and cache', () async {
        // Arrange
        mockDb.mockEvent = Event(
          id: 1,
          bookId: 10,
          name: 'Test Event',
          recordNumber: 'REC001',
          eventType: 'appointment',
          startTime: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        mockDb.mockCredentials = const DeviceCredentials(
          deviceId: 'device123',
          deviceToken: 'token123',
        );
        mockCacheManager.mockNotes[1] = Note(
          eventId: 1,
          strokes: const [],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        // Act
        await contentService.deleteNote(1);

        // Assert
        expect(mockApiClient.deleteNoteCalled, true);
        expect(mockCacheManager.mockNotes.containsKey(1), false);
      });

      // Phase 4-01 Tests: Cache-only and sync methods
      test('getCachedNote - returns note from cache without network call', () async {
        // Arrange
        final cachedNote = Note(
          eventId: 1,
          strokes: const [Stroke(points: [StrokePoint(10, 10)])],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          isDirty: true,
        );
        mockCacheManager.mockNotes[1] = cachedNote;

        // Act
        final result = await contentService.getCachedNote(1);

        // Assert
        expect(result, isNotNull);
        expect(result!.eventId, 1);
        expect(result.isDirty, true);
        expect(mockApiClient.fetchNoteCalled, false,
            reason: 'getCachedNote should not call API');
      });

      test('getCachedNote - returns null when cache is empty', () async {
        // Act
        final result = await contentService.getCachedNote(999);

        // Assert
        expect(result, isNull);
        expect(mockApiClient.fetchNoteCalled, false);
      });

      test('syncNote - syncs dirty note to server and marks clean', () async {
        // Arrange
        final dirtyNote = Note(
          eventId: 1,
          strokes: const [Stroke(points: [StrokePoint(25, 25)])],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          isDirty: true,
        );
        mockCacheManager.mockNotes[1] = dirtyNote;
        mockDb.mockEvent = Event(
          id: 1,
          bookId: 10,
          name: 'Test Event',
          recordNumber: 'REC001',
          eventType: 'appointment',
          startTime: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        mockDb.mockCredentials = const DeviceCredentials(
          deviceId: 'device123',
          deviceToken: 'token123',
        );

        // Act
        await contentService.syncNote(1);

        // Assert
        expect(mockApiClient.saveNoteCalled, true);
        expect(mockCacheManager.cleanedNoteIds.contains(1), true,
            reason: 'Should mark note as clean after successful sync');
      });

      test('syncNote - throws error and keeps dirty flag when sync fails', () async {
        // Arrange
        final dirtyNote = Note(
          eventId: 1,
          strokes: const [Stroke(points: [StrokePoint(30, 30)])],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          isDirty: true,
        );
        mockCacheManager.mockNotes[1] = dirtyNote;
        mockDb.mockEvent = Event(
          id: 1,
          bookId: 10,
          name: 'Test Event',
          recordNumber: 'REC001',
          eventType: 'appointment',
          startTime: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        mockDb.mockCredentials = const DeviceCredentials(
          deviceId: 'device123',
          deviceToken: 'token123',
        );
        mockApiClient.shouldThrowError = true;

        // Act & Assert
        expect(() => contentService.syncNote(1), throwsException);
        expect(mockCacheManager.cleanedNoteIds.contains(1), false,
            reason: 'Should NOT mark note as clean when sync fails');
      });

      test('syncNote - does nothing when note not found in cache', () async {
        // Act
        await contentService.syncNote(999);

        // Assert
        expect(mockApiClient.saveNoteCalled, false,
            reason: 'Should not attempt sync when note not in cache');
      });
    });

    group('Drawings Operations', () {
      test('getDrawing - cache hit returns cached drawing', () async {
        // Arrange
        final cachedDrawing = ScheduleDrawing(
          bookId: 10,
          date: DateTime(2025, 10, 24),
          viewMode: 0,
          strokes: const [Stroke(points: [StrokePoint(15, 15)])],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        mockCacheManager.mockDrawings['10-2025-10-24-0'] = cachedDrawing;

        // Act
        final result = await contentService.getDrawing(
          bookId: 10,
          date: DateTime(2025, 10, 24),
          viewMode: 0,
        );

        // Assert
        expect(result, isNotNull);
        expect(result!.bookId, 10);
        expect(result.strokes.length, 1);
        expect(mockApiClient.fetchDrawingCalled, false);
      });

      test('getDrawing - cache miss fetches from server and caches', () async {
        // Arrange
        mockDb.mockCredentials = const DeviceCredentials(
          deviceId: 'device123',
          deviceToken: 'token123',
        );
        mockApiClient.mockDrawingResponse = {
          'book_id': 10,
          'date': 1729728000,
          'view_mode': 0,
          'strokes_data': '[{"points":[{"dx":25.0,"dy":25.0,"pressure":1.0}],"stroke_width":2.0,"color":4278190080}]',
          'created_at': 1234567890,
          'updated_at': 1234567890,
        };

        // Act
        final result = await contentService.getDrawing(
          bookId: 10,
          date: DateTime(2025, 10, 24),
          viewMode: 0,
        );

        // Assert
        expect(result, isNotNull);
        expect(result!.bookId, 10);
        expect(mockApiClient.fetchDrawingCalled, true);
        expect(mockCacheManager.savedDrawings.isNotEmpty, true);
      });

      test('saveDrawing - saves to server and cache', () async {
        // Arrange
        mockDb.mockCredentials = const DeviceCredentials(
          deviceId: 'device123',
          deviceToken: 'token123',
        );
        final drawing = ScheduleDrawing(
          bookId: 10,
          date: DateTime(2025, 10, 24),
          viewMode: 0,
          strokes: const [Stroke(points: [StrokePoint(30, 30)])],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        // Act
        await contentService.saveDrawing(drawing);

        // Assert
        expect(mockApiClient.saveDrawingCalled, true);
        expect(mockCacheManager.savedDrawings.isNotEmpty, true);
      });

      test('deleteDrawing - deletes from server and cache', () async {
        // Arrange
        mockDb.mockCredentials = const DeviceCredentials(
          deviceId: 'device123',
          deviceToken: 'token123',
        );
        mockCacheManager.mockDrawings['10-2025-10-24-0'] = ScheduleDrawing(
          bookId: 10,
          date: DateTime(2025, 10, 24),
          viewMode: 0,
          strokes: const [],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        // Act
        await contentService.deleteDrawing(
          bookId: 10,
          date: DateTime(2025, 10, 24),
          viewMode: 0,
        );

        // Assert
        expect(mockApiClient.deleteDrawingCalled, true);
        expect(mockCacheManager.mockDrawings.containsKey('10-2025-10-24-0'), false);
      });
    });
  });
}

// ===================
// Mock Classes
// ===================

class _MockApiClient extends ApiClient {
  _MockApiClient() : super(baseUrl: 'http://mock');

  bool fetchNoteCalled = false;
  bool saveNoteCalled = false;
  bool deleteNoteCalled = false;
  bool fetchDrawingCalled = false;
  bool saveDrawingCalled = false;
  bool deleteDrawingCalled = false;
  bool shouldThrowError = false;

  Map<String, dynamic>? mockNoteResponse;
  Map<String, dynamic>? mockDrawingResponse;

  @override
  Future<Map<String, dynamic>?> fetchNote({
    required int bookId,
    required int eventId,
    required String deviceId,
    required String deviceToken,
  }) async {
    fetchNoteCalled = true;
    if (shouldThrowError) {
      throw ApiException('Network error');
    }
    return mockNoteResponse;
  }

  @override
  Future<Map<String, dynamic>> saveNote({
    required int bookId,
    required int eventId,
    required Map<String, dynamic> noteData,
    required String deviceId,
    required String deviceToken,
  }) async {
    saveNoteCalled = true;
    if (shouldThrowError) {
      throw ApiException('Network error');
    }
    return noteData;
  }

  @override
  Future<void> deleteNote({
    required int bookId,
    required int eventId,
    required String deviceId,
    required String deviceToken,
  }) async {
    deleteNoteCalled = true;
    if (shouldThrowError) {
      throw ApiException('Network error');
    }
  }

  @override
  Future<Map<String, dynamic>?> fetchDrawing({
    required int bookId,
    required DateTime date,
    required int viewMode,
    required String deviceId,
    required String deviceToken,
  }) async {
    fetchDrawingCalled = true;
    if (shouldThrowError) {
      throw ApiException('Network error');
    }
    return mockDrawingResponse;
  }

  @override
  Future<Map<String, dynamic>> saveDrawing({
    required int bookId,
    required Map<String, dynamic> drawingData,
    required String deviceId,
    required String deviceToken,
  }) async {
    saveDrawingCalled = true;
    if (shouldThrowError) {
      throw ApiException('Network error');
    }
    return drawingData;
  }

  @override
  Future<void> deleteDrawing({
    required int bookId,
    required DateTime date,
    required int viewMode,
    required String deviceId,
    required String deviceToken,
  }) async {
    deleteDrawingCalled = true;
    if (shouldThrowError) {
      throw ApiException('Network error');
    }
  }
}

class _MockCacheManager {
  final Map<int, Note> mockNotes = {};
  final Map<String, ScheduleDrawing> mockDrawings = {};
  final Map<int, Note> savedNotes = {};
  final List<ScheduleDrawing> savedDrawings = [];
  final Set<int> cleanedNoteIds = {}; // Track notes marked as clean (Phase 4-01)

  Future<Note?> getNote(int eventId) async {
    return mockNotes[eventId];
  }

  Future<void> saveNote(int eventId, Note note, {bool dirty = false}) async {
    final noteToSave = dirty ? note.copyWith(isDirty: true) : note;
    savedNotes[eventId] = noteToSave;
    mockNotes[eventId] = noteToSave;
  }

  // Phase 4-01: Mark note as clean (synced to server)
  Future<void> markNoteClean(int eventId) async {
    final note = mockNotes[eventId];
    if (note != null) {
      mockNotes[eventId] = note.copyWith(isDirty: false);
      cleanedNoteIds.add(eventId);
    }
  }

  Future<void> deleteNote(int eventId) async {
    mockNotes.remove(eventId);
  }

  Future<ScheduleDrawing?> getDrawing(
      int bookId, DateTime date, int viewMode) async {
    final key = '$bookId-${date.year}-${date.month}-${date.day}-$viewMode';
    return mockDrawings[key];
  }

  Future<void> saveDrawing(ScheduleDrawing drawing) async {
    savedDrawings.add(drawing);
    final key =
        '${drawing.bookId}-${drawing.date.year}-${drawing.date.month}-${drawing.date.day}-${drawing.viewMode}';
    mockDrawings[key] = drawing;
  }

  Future<void> deleteDrawing(int bookId, DateTime date, int viewMode) async {
    final key = '$bookId-${date.year}-${date.month}-${date.day}-$viewMode';
    mockDrawings.remove(key);
  }
}

class _MockDatabase {
  Event? mockEvent;
  DeviceCredentials? mockCredentials;

  Future<Event?> getEventById(int id) async {
    return mockEvent;
  }

  Future<DeviceCredentials?> getDeviceCredentials() async {
    return mockCredentials;
  }
}
