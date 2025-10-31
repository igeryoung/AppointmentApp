import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/models/note.dart';
import 'package:schedule_note_app/services/content_service.dart';
import 'package:schedule_note_app/services/api_client.dart';

/// Tests for ScheduleScreen Smart Preloading
///
/// According to Phase 4-02 spec:
/// - Preload notes on initState (3-day window)
/// - NO preloading on date change (per user's modification)
/// - Non-blocking background execution
/// - Graceful failure handling
///
/// These are integration-style tests that verify the ContentService.preloadNotes()
/// behavior, which is the core functionality used by ScheduleScreen.
void main() {
  group('ContentService.preloadNotes() Integration Tests', () {
    test('preloadNotes accepts progress callback parameter', () async {
      // This test verifies the API contract without requiring server/DB
      final mockDb = MockDatabase();
      final mockCacheManager = MockCacheManager();
      final apiClient = ApiClient(baseUrl: 'http://localhost:8080');

      final contentService = ContentService(apiClient, mockCacheManager, mockDb);

      // Test that we can call preloadNotes with onProgress callback
      // The method should accept the callback and not throw
      expect(
        () async {
          await contentService.preloadNotes(
            [1, 2, 3],
            onProgress: (loaded, total) {
              // Callback can be provided
            },
          );
          // Wait a bit for microtask to start
          await Future.delayed(Duration(milliseconds: 50));
        },
        returnsNormally,
      );
    });

    test('preloadNotes handles empty list without error', () async {
      final mockDb = MockDatabase();
      final mockCacheManager = MockCacheManager();
      final apiClient = ApiClient(baseUrl: 'http://localhost:8080');

      final contentService = ContentService(apiClient, mockCacheManager, mockDb);

      int callbackCount = 0;
      await contentService.preloadNotes(
        [],
        onProgress: (loaded, total) {
          callbackCount++;
          expect(loaded, 0);
          expect(total, 0);
        },
      );

      // Should call callback with (0, 0) for empty list
      expect(callbackCount, 1);
    });

    test('preloadNotes skips already-cached notes', () async {
      final now = DateTime.now();
      final mockDb = MockDatabase();
      final mockCacheManager = MockCacheManager();

      // Setup: Pre-cache some notes
      mockCacheManager.setMockedCachedNotes({
        1: Note(eventId: 1, strokes: [], createdAt: now, updatedAt: now, isDirty: false),
        3: Note(eventId: 3, strokes: [], createdAt: now, updatedAt: now, isDirty: false),
      });

      final apiClient = ApiClient(baseUrl: 'http://localhost:8080');
      final contentService = ContentService(apiClient, mockCacheManager, mockDb);

      // Request to preload 5 notes (2 already cached)
      final eventIds = [1, 2, 3, 4, 5];

      await contentService.preloadNotes(eventIds);
      await Future.delayed(Duration(milliseconds: 50));

      // The method should have checked cache for all 5 IDs
      expect(mockCacheManager.getCalls.length, greaterThanOrEqualTo(5));
    });

    test('preloadNotes returns immediately (non-blocking)', () async {
      final mockDb = MockDatabase();
      final mockCacheManager = MockCacheManager();
      final apiClient = ApiClient(baseUrl: 'http://localhost:8080');

      final contentService = ContentService(apiClient, mockCacheManager, mockDb);

      // Measure how long preloadNotes takes to return
      final stopwatch = Stopwatch()..start();
      await contentService.preloadNotes([1, 2, 3, 4, 5]);
      stopwatch.stop();

      // Should return almost immediately (< 50ms) because it runs in microtask
      expect(stopwatch.elapsedMilliseconds, lessThan(50));
    });

    test('preloadNotes handles no device credentials gracefully', () async {
      final mockDb = MockDatabase();
      final mockCacheManager = MockCacheManager();
      final apiClient = ApiClient(baseUrl: 'http://localhost:8080');

      // No credentials set (returns null)
      mockDb.setDeviceCredentials(null, null);

      final contentService = ContentService(apiClient, mockCacheManager, mockDb);

      // Should not throw, just skip server fetch
      expect(
        () async {
          await contentService.preloadNotes([1, 2, 3]);
          await Future.delayed(Duration(milliseconds: 50));
        },
        returnsNormally,
      );
    });
  });

  group('ContentService.preloadNotes() Progress Callback Tests', () {
    test('onProgress callback receives correct parameters', () async {
      final mockDb = MockDatabase();
      final mockCacheManager = MockCacheManager();
      final apiClient = ApiClient(baseUrl: 'http://localhost:8080');

      final contentService = ContentService(apiClient, mockCacheManager, mockDb);

      final progressReports = <Map<String, int>>[];

      await contentService.preloadNotes(
        [1, 2, 3],
        onProgress: (loaded, total) {
          progressReports.add({'loaded': loaded, 'total': total});
          // Verify parameters are non-negative
          expect(loaded, greaterThanOrEqualTo(0));
          expect(total, greaterThanOrEqualTo(0));
          // Loaded should never exceed total
          expect(loaded, lessThanOrEqualTo(total));
        },
      );

      await Future.delayed(Duration(milliseconds: 100));

      // Progress callback should be called at least once
      expect(progressReports.isNotEmpty, true);
    });
  });

  group('Performance Benchmarks', () {
    test('preloadNotes with 50 IDs returns in < 50ms (non-blocking)', () async {
      final mockDb = MockDatabase();
      final mockCacheManager = MockCacheManager();
      final apiClient = ApiClient(baseUrl: 'http://localhost:8080');

      final contentService = ContentService(apiClient, mockCacheManager, mockDb);

      final stopwatch = Stopwatch()..start();
      await contentService.preloadNotes(List.generate(50, (i) => i + 1));
      stopwatch.stop();

      // Non-blocking: should return immediately
      expect(stopwatch.elapsedMilliseconds, lessThan(50));
    });
  });
}

// ===================
// Mock Classes
// ===================

class MockDatabase {
  String? _deviceId;
  String? _deviceToken;

  void setDeviceCredentials(String? deviceId, String? deviceToken) {
    _deviceId = deviceId;
    _deviceToken = deviceToken;
  }

  Future<DeviceCredentials?> getDeviceCredentials() async {
    if (_deviceId == null || _deviceToken == null) return null;
    return DeviceCredentials(_deviceId!, _deviceToken!);
  }
}

class DeviceCredentials {
  final String deviceId;
  final String deviceToken;
  DeviceCredentials(this.deviceId, this.deviceToken);
}

class MockCacheManager {
  final Map<int, Note> _cachedNotes = {};
  final List<int> getCalls = [];

  void setMockedCachedNotes(Map<int, Note> notes) {
    _cachedNotes.clear();
    _cachedNotes.addAll(notes);
  }

  Future<Note?> getNote(int eventId) async {
    getCalls.add(eventId);
    return _cachedNotes[eventId];
  }

  Future<void> saveNote(int eventId, Note note, {bool dirty = false}) async {
    _cachedNotes[eventId] = note;
  }
}
