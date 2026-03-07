@Tags(['drawing', 'unit'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/models/note.dart';
import 'package:schedule_note_app/models/schedule_drawing.dart';
import 'package:schedule_note_app/repositories/device_repository.dart';
import 'package:schedule_note_app/services/api_client.dart';
import 'package:schedule_note_app/services/content_service.dart';
import 'package:schedule_note_app/services/database/prd_database_service.dart';
import 'package:schedule_note_app/services/drawing_content_service.dart';

class _FakeDeviceRepository implements IDeviceRepository {
  _FakeDeviceRepository(this._credentials);

  final DeviceCredentials? _credentials;

  @override
  Future<DeviceCredentials?> getCredentials() async => _credentials;

  @override
  Future<void> saveCredentials({
    required String deviceId,
    required String deviceToken,
    required String deviceName,
    String? platform,
    String deviceRole = 'read',
  }) async {}
}

class _FakeDb {
  _FakeDb(this._credentials);

  final DeviceCredentials? _credentials;

  Future<DeviceCredentials?> getDeviceCredentials() async => _credentials;
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(baseUrl: 'http://localhost:8080');

  final List<Map<String, dynamic>> saveRequests = [];
  final List<Object> saveOutcomes = [];
  Map<String, dynamic>? fetchDrawingResponse;
  int fetchDrawingCalls = 0;

  @override
  Future<Map<String, dynamic>> saveDrawing({
    required String bookUuid,
    required Map<String, dynamic> drawingData,
    required String deviceId,
    required String deviceToken,
  }) async {
    saveRequests.add(Map<String, dynamic>.from(drawingData));
    if (saveOutcomes.isEmpty) {
      throw StateError('No save outcome queued');
    }

    final next = saveOutcomes.removeAt(0);
    if (next is Exception) {
      throw next;
    }
    if (next is Error) {
      throw next;
    }
    return Map<String, dynamic>.from(next as Map);
  }

  @override
  Future<Map<String, dynamic>?> fetchDrawing({
    required String bookUuid,
    required DateTime date,
    required int viewMode,
    required String deviceId,
    required String deviceToken,
  }) async {
    fetchDrawingCalls += 1;
    return fetchDrawingResponse;
  }
}

Stroke _stroke(String id) {
  return Stroke(
    id: id,
    points: const [StrokePoint(1, 1), StrokePoint(2, 2)],
    strokeType: StrokeType.pen,
    strokeWidth: 2,
    color: 0xFF000000,
  );
}

ScheduleDrawing _drawing({
  required String strokeId,
  required int version,
  int id = 11,
}) {
  final now = DateTime.utc(2026, 3, 5, 10, 0, 0);
  return ScheduleDrawing(
    id: id,
    bookUuid: 'book-lww',
    date: DateTime.utc(2026, 3, 5),
    viewMode: ScheduleDrawing.VIEW_MODE_2DAY,
    strokes: [_stroke(strokeId)],
    version: version,
    createdAt: now,
    updatedAt: now,
  );
}

Map<String, dynamic> _serverDrawing({
  required String strokeId,
  required int version,
  int id = 11,
}) {
  final now = DateTime.utc(2026, 3, 5, 10, 0, 0).toIso8601String();
  return {
    'id': id,
    'bookUuid': 'book-lww',
    'date': DateTime.utc(2026, 3, 5).toIso8601String(),
    'viewMode': ScheduleDrawing.VIEW_MODE_2DAY,
    'strokesData': jsonEncode([_stroke(strokeId).toMap()]),
    'createdAt': now,
    'updatedAt': now,
    'version': version,
  };
}

void main() {
  late _FakeApiClient apiClient;

  setUp(() {
    apiClient = _FakeApiClient();
  });

  tearDown(() {
    apiClient.dispose();
  });

  test(
    'DRAWING-LWW-UNIT-001: DrawingContentService conflict retry uses serverVersion+1 and preserves local payload',
    () async {
      final repository = _FakeDeviceRepository(
        const DeviceCredentials(deviceId: 'd1', deviceToken: 't1'),
      );
      final service = DrawingContentService(apiClient, repository);

      apiClient.saveOutcomes.add(
        ApiConflictException(
          'Drawing version conflict',
          statusCode: 409,
          responseBody: jsonEncode({
            'conflict': true,
            'serverVersion': 5,
            'serverDrawing': _serverDrawing(
              strokeId: 'server-stroke',
              version: 5,
            ),
          }),
        ),
      );
      apiClient.saveOutcomes.add(
        _serverDrawing(strokeId: 'local-stroke', version: 6),
      );

      final saved = await service.saveDrawing(
        _drawing(strokeId: 'local-stroke', version: 4),
      );

      expect(apiClient.saveRequests.length, 2);
      expect(apiClient.saveRequests[0]['version'], 4);
      expect(apiClient.saveRequests[1]['version'], 6);
      expect(apiClient.fetchDrawingCalls, 0);

      final retryPayload = apiClient.saveRequests[1]['strokesData'] as String;
      expect(retryPayload, contains('local-stroke'));
      expect(retryPayload, isNot(contains('server-stroke')));
      expect(saved.version, 6);
    },
  );

  test(
    'DRAWING-LWW-UNIT-002: ContentService conflict retry uses serverVersion+1 and preserves local payload',
    () async {
      final service = ContentService(
        apiClient,
        _FakeDb(const DeviceCredentials(deviceId: 'd1', deviceToken: 't1')),
      );

      apiClient.saveOutcomes.add(
        ApiConflictException(
          'Drawing version conflict',
          statusCode: 409,
          responseBody: jsonEncode({
            'conflict': true,
            'serverVersion': 8,
            'serverDrawing': _serverDrawing(
              strokeId: 'server-stroke',
              version: 8,
            ),
          }),
        ),
      );
      apiClient.saveOutcomes.add(
        _serverDrawing(strokeId: 'local-stroke', version: 9),
      );

      final saved = await service.saveDrawing(
        _drawing(strokeId: 'local-stroke', version: 7),
      );

      expect(apiClient.saveRequests.length, 2);
      expect(apiClient.saveRequests[0]['version'], 7);
      expect(apiClient.saveRequests[1]['version'], 9);

      final retryPayload = apiClient.saveRequests[1]['strokesData'] as String;
      expect(retryPayload, contains('local-stroke'));
      expect(retryPayload, isNot(contains('server-stroke')));
      expect(saved.version, 9);
    },
  );

  test(
    'DRAWING-LWW-UNIT-003: DrawingContentService falls back to fetch when conflict response has no serverVersion',
    () async {
      final repository = _FakeDeviceRepository(
        const DeviceCredentials(deviceId: 'd1', deviceToken: 't1'),
      );
      final service = DrawingContentService(apiClient, repository);

      apiClient.fetchDrawingResponse = _serverDrawing(
        strokeId: 'server-stroke',
        version: 3,
      );
      apiClient.saveOutcomes.add(
        ApiConflictException(
          'Drawing version conflict',
          statusCode: 409,
          responseBody: jsonEncode({'conflict': true}),
        ),
      );
      apiClient.saveOutcomes.add(
        _serverDrawing(strokeId: 'local-stroke', version: 4),
      );

      final saved = await service.saveDrawing(
        _drawing(strokeId: 'local-stroke', version: 2),
      );

      expect(apiClient.fetchDrawingCalls, 1);
      expect(apiClient.saveRequests.length, 2);
      expect(apiClient.saveRequests[1]['version'], 4);
      expect(saved.version, 4);
    },
  );
}
