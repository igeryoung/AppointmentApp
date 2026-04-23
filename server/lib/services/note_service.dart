import 'dart:convert';

import '../database/connection.dart';
import 'account_auth_service.dart';
import 'book_access_service.dart';

class NoteOperationResult {
  final bool success;
  final Map<String, dynamic>? note;
  final bool hasConflict;
  final int? serverVersion;
  final Map<String, dynamic>? serverNote;

  const NoteOperationResult({
    required this.success,
    this.note,
    this.hasConflict = false,
    this.serverVersion,
    this.serverNote,
  });

  NoteOperationResult.success(Map<String, dynamic> note)
    : success = true,
      note = note,
      hasConflict = false,
      serverVersion = null,
      serverNote = null;

  NoteOperationResult.conflict({
    required int serverVersion,
    required Map<String, dynamic> serverNote,
  }) : success = false,
       note = null,
       hasConflict = true,
       serverVersion = serverVersion,
       serverNote = serverNote;

  NoteOperationResult.notFound()
    : success = false,
      note = null,
      hasConflict = false,
      serverVersion = null,
      serverNote = null;
}

class NoteService {
  static const String roleRead = 'read';
  static const String roleWrite = 'write';

  final DatabaseConnection db;
  late final BookAccessService _bookAccessService;
  late final AccountAuthService _accountAuth;

  NoteService(this.db) {
    _bookAccessService = BookAccessService(db);
    _accountAuth = AccountAuthService(db);
  }

  DateTime _asUtc(dynamic value) {
    if (value is DateTime) return value.isUtc ? value : value.toUtc();
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null)
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return parsed.isUtc ? parsed : parsed.toUtc();
  }

  Map<String, dynamic>? _first(dynamic data) {
    if (data is List && data.isNotEmpty) {
      final row = data.first;
      if (row is Map<String, dynamic>) return row;
      if (row is Map) return Map<String, dynamic>.from(row);
    }
    return null;
  }

  List<Map<String, dynamic>> _rows(dynamic data) {
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<bool> verifyDeviceAccess(String deviceId, String token) async {
    return _accountAuth.verifyDeviceAccess(deviceId, token);
  }

  Future<bool> verifyBookOwnership(String deviceId, String bookUuid) async {
    return verifyBookAccess(deviceId, bookUuid);
  }

  Future<String> getDeviceRole(String deviceId) async {
    return _accountAuth.getAccountRoleForDevice(deviceId);
  }

  Future<bool> canDeviceWrite(String deviceId) async {
    final role = await getDeviceRole(deviceId);
    return role == roleWrite;
  }

  Future<bool> verifyBookAccess(
    String deviceId,
    String bookUuid, {
    bool requireWrite = false,
  }) async {
    try {
      return _bookAccessService.verifyBookAccess(
        deviceId,
        bookUuid,
        requireWrite: requireWrite,
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> verifyEventInBook(String eventId, String bookUuid) async {
    try {
      final rows = await db.client
          .from('events')
          .select('id')
          .eq('id', eventId)
          .eq('book_uuid', bookUuid)
          .eq('is_deleted', false)
          .limit(1);
      return _first(rows) != null;
    } catch (_) {
      return false;
    }
  }

  Future<String?> getRecordUuidByEvent({
    required String bookUuid,
    required String eventId,
  }) async {
    final rows = await db.client
        .from('events')
        .select('record_uuid')
        .eq('id', eventId)
        .eq('book_uuid', bookUuid)
        .eq('is_deleted', false)
        .limit(1);
    final row = _first(rows);
    return row?['record_uuid']?.toString();
  }

  Future<Map<String, dynamic>?> getNoteByRecordUuid(String recordUuid) async {
    final rows = await db.client
        .from('notes')
        .select('id, record_uuid, pages_data, created_at, updated_at, version')
        .eq('record_uuid', recordUuid)
        .eq('is_deleted', false)
        .limit(1);

    final row = _first(rows);
    if (row == null) return null;

    return {
      'id': row['id'],
      'record_uuid': row['record_uuid'],
      'pages_data': row['pages_data'],
      'created_at': _asUtc(row['created_at']).toIso8601String(),
      'updated_at': _asUtc(row['updated_at']).toIso8601String(),
      'version': (row['version'] as num?)?.toInt() ?? 1,
    };
  }

  Future<NoteOperationResult> createOrUpdateNoteForRecord({
    required String recordUuid,
    required String pagesData,
    int? expectedVersion,
  }) async {
    try {
      final allRows = await db.client
          .from('notes')
          .select(
            'id, record_uuid, pages_data, created_at, updated_at, version, is_deleted',
          )
          .eq('record_uuid', recordUuid)
          .limit(1);

      final existing = _first(allRows);
      Map<String, dynamic> saved;

      if (existing == null) {
        final inserted = await db.client
            .from('notes')
            .insert({
              'record_uuid': recordUuid,
              'pages_data': pagesData,
              'version': 1,
              'created_at': DateTime.now().toUtc().toIso8601String(),
              'updated_at': DateTime.now().toUtc().toIso8601String(),
              'synced_at': DateTime.now().toUtc().toIso8601String(),
              'is_deleted': false,
            })
            .select(
              'id, record_uuid, pages_data, created_at, updated_at, version',
            )
            .limit(1);
        final row = _first(inserted);
        if (row == null) return NoteOperationResult.notFound();
        saved = row;
      } else {
        final isDeleted = existing['is_deleted'] == true;
        if (isDeleted) {
          return NoteOperationResult.notFound();
        }

        final serverVersion = (existing['version'] as num?)?.toInt() ?? 1;
        if (expectedVersion != null && serverVersion != expectedVersion) {
          return NoteOperationResult.conflict(
            serverVersion: serverVersion,
            serverNote: {
              'id': existing['id'],
              'record_uuid': existing['record_uuid'],
              'pages_data': existing['pages_data'],
              'created_at': _asUtc(existing['created_at']).toIso8601String(),
              'updated_at': _asUtc(existing['updated_at']).toIso8601String(),
              'version': serverVersion,
            },
          );
        }

        final updated = await db.client
            .from('notes')
            .update({
              'pages_data': pagesData,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
              'synced_at': DateTime.now().toUtc().toIso8601String(),
              'version': serverVersion + 1,
              'is_deleted': false,
            })
            .eq('id', existing['id'])
            .select(
              'id, record_uuid, pages_data, created_at, updated_at, version',
            )
            .limit(1);
        final row = _first(updated);
        if (row == null) return NoteOperationResult.notFound();
        saved = row;
      }

      // Update has_note per event based on per-event strokes and erase map.
      dynamic decoded;
      try {
        decoded = jsonDecode(pagesData);
      } catch (_) {
        decoded = <String, dynamic>{'pages': <dynamic>[]};
      }

      final pages =
          (decoded is Map ? decoded['pages'] : decoded) as List? ?? [];
      final erasedByEvent = decoded is Map
          ? (decoded['erasedStrokesByEvent'] as Map<String, dynamic>? ??
                <String, dynamic>{})
          : <String, dynamic>{};

      final strokesByEvent = <String, Set<String>>{};
      for (final page in pages) {
        if (page is! List) continue;
        for (final stroke in page) {
          if (stroke is! Map) continue;
          final eventUuid = stroke['event_uuid']?.toString();
          final strokeId = stroke['id']?.toString();
          if (eventUuid != null && eventUuid.isNotEmpty && strokeId != null) {
            strokesByEvent
                .putIfAbsent(eventUuid, () => <String>{})
                .add(strokeId);
          }
        }
      }

      final eventsRows = await db.client
          .from('events')
          .select('id')
          .eq('record_uuid', recordUuid)
          .eq('is_deleted', false);

      for (final event in _rows(eventsRows)) {
        final eventId = event['id'].toString();
        final eventStrokes = strokesByEvent[eventId] ?? <String>{};
        final erasedStrokes = Set<String>.from(
          (erasedByEvent[eventId] as List?)?.map((e) => e.toString()) ??
              const <String>[],
        );
        final hasNote = eventStrokes.any((id) => !erasedStrokes.contains(id));

        await db.client
            .from('events')
            .update({
              'has_note': hasNote,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', eventId);
      }

      return NoteOperationResult.success({
        'id': saved['id'],
        'record_uuid': saved['record_uuid'],
        'pages_data': saved['pages_data'],
        'created_at': _asUtc(saved['created_at']).toIso8601String(),
        'updated_at': _asUtc(saved['updated_at']).toIso8601String(),
        'version': (saved['version'] as num?)?.toInt() ?? 1,
      });
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> deleteNoteByRecordUuid(String recordUuid) async {
    final existingRows = await db.client
        .from('notes')
        .select('id')
        .eq('record_uuid', recordUuid)
        .eq('is_deleted', false)
        .limit(1);

    final existing = _first(existingRows);
    if (existing == null) return false;

    await db.client
        .from('notes')
        .update({
          'is_deleted': true,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'synced_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', existing['id']);

    await db.client
        .from('events')
        .update({
          'has_note': false,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('record_uuid', recordUuid);

    return true;
  }

  Future<List<Map<String, dynamic>>> batchGetNotesByRecordUuids({
    required List<String> recordUuids,
  }) async {
    if (recordUuids.isEmpty) return const [];

    final notesRows = await db.client
        .from('notes')
        .select('id, record_uuid, pages_data, created_at, updated_at, version')
        .inFilter('record_uuid', recordUuids)
        .eq('is_deleted', false)
        .order('record_uuid', ascending: true);

    return _rows(notesRows)
        .map(
          (row) => {
            'id': row['id'],
            'record_uuid': row['record_uuid'],
            'pages_data': row['pages_data'],
            'created_at': _asUtc(row['created_at']).toIso8601String(),
            'updated_at': _asUtc(row['updated_at']).toIso8601String(),
            'version': (row['version'] as num?)?.toInt() ?? 1,
          },
        )
        .toList();
  }

  Future<String?> getOrCreateRecordFromEventData(
    Map<String, dynamic> eventData,
  ) async {
    final recordUuid = eventData['record_uuid']?.toString().trim();
    if (recordUuid == null || recordUuid.isEmpty) return null;

    final existingRows = await db.client
        .from('records')
        .select('record_uuid')
        .eq('record_uuid', recordUuid)
        .limit(1);
    if (_first(existingRows) != null) {
      return recordUuid;
    }

    final recordNumber = (eventData['record_number'] ?? '').toString();
    final name = (eventData['title'] ?? '').toString();

    await db.client.from('records').insert({
      'record_uuid': recordUuid,
      'record_number': recordNumber,
      'name': name,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'synced_at': DateTime.now().toUtc().toIso8601String(),
      'version': 1,
      'is_deleted': false,
    });

    return recordUuid;
  }

  Future<void> createEventIfAbsent({
    required String eventId,
    required String bookUuid,
    required String recordUuid,
    required Map<String, dynamic> eventData,
  }) async {
    final existingRows = await db.client
        .from('events')
        .select('id')
        .eq('id', eventId)
        .limit(1);
    if (_first(existingRows) != null) return;

    final title = (eventData['title'] ?? '').toString();
    final eventTypesRaw = eventData['event_types'];
    final eventTypes = eventTypesRaw is String
        ? eventTypesRaw
        : jsonEncode(eventTypesRaw ?? ['other']);
    final hasChargeItems =
        eventData['has_charge_items'] == true ||
        eventData['has_charge_items'] == 1;

    final startTimeSeconds = int.tryParse(
      (eventData['start_time'] ?? '').toString(),
    );
    final endTimeSeconds = int.tryParse(
      (eventData['end_time'] ?? '').toString(),
    );
    final now = DateTime.now().toUtc();
    final startTime = startTimeSeconds != null
        ? DateTime.fromMillisecondsSinceEpoch(
            startTimeSeconds * 1000,
            isUtc: true,
          )
        : now;
    final endTime = endTimeSeconds != null
        ? DateTime.fromMillisecondsSinceEpoch(
            endTimeSeconds * 1000,
            isUtc: true,
          )
        : null;

    await db.client.from('events').insert({
      'id': eventId,
      'book_uuid': bookUuid,
      'record_uuid': recordUuid,
      'title': title,
      'event_types': eventTypes,
      'has_charge_items': hasChargeItems,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'synced_at': now.toIso8601String(),
      'version': 1,
      'is_deleted': false,
      'is_removed': false,
      'is_checked': false,
      'has_note': false,
    });
  }
}
