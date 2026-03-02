library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/models/event.dart';
import 'package:schedule_note_app/models/event_type.dart';
import 'package:schedule_note_app/models/note.dart';
import 'package:schedule_note_app/screens/event_detail/adapters/note_sync_adapter.dart';
import 'package:schedule_note_app/screens/event_detail/event_detail_controller.dart';
import 'package:schedule_note_app/services/api_client.dart';
import 'package:schedule_note_app/services/content_service.dart';
import 'package:schedule_note_app/services/database/prd_database_service.dart';

class _NoopApiClient extends ApiClient {
  _NoopApiClient() : super(baseUrl: 'http://benchmark.local');
}

class _DelayedNoteSyncAdapter extends NoteSyncAdapter {
  _DelayedNoteSyncAdapter(
    super.contentService, {
    required this.fetchDelay,
    required this.saveDelay,
  });

  final Duration fetchDelay;
  final Duration saveDelay;

  Note? serverNote;
  int fetchCalls = 0;
  int saveCalls = 0;

  @override
  Future<Note?> getNoteByRecordUuid(String bookUuid, String recordUuid) async {
    fetchCalls += 1;
    await Future<void>.delayed(fetchDelay);
    return serverNote;
  }

  @override
  Future<Note> saveNote(String eventId, Note note) async {
    saveCalls += 1;
    await Future<void>.delayed(saveDelay);
    return note;
  }
}

Event _buildEvent({required String eventId, required String recordUuid}) {
  return Event(
    id: eventId,
    bookUuid: 'book-bench',
    recordUuid: recordUuid,
    title: 'Bench User',
    recordNumber: 'BENCH-001',
    eventTypes: const [EventType.consultation],
    startTime: DateTime.utc(2026, 3, 2, 9),
    endTime: DateTime.utc(2026, 3, 2, 9, 30),
    createdAt: DateTime.utc(2026, 3, 2, 9),
    updatedAt: DateTime.utc(2026, 3, 2, 9),
  );
}

List<List<Stroke>> _buildPages(String eventId) {
  return [
    [
      Stroke(
        id: 'bench-stroke-$eventId',
        eventUuid: eventId,
        points: const [StrokePoint(1, 1), StrokePoint(20, 20)],
      ),
    ],
  ];
}

Future<Note> _legacySaveNoteToServer({
  required _DelayedNoteSyncAdapter adapter,
  required Event event,
  required List<List<Stroke>> pages,
  required Note? localStateNote,
  Map<String, List<String>> erasedStrokesByEvent = const {},
  Size? canvasSize,
}) async {
  Note? baseNote;
  if (event.recordUuid.isNotEmpty) {
    baseNote = await adapter.getNoteByRecordUuid(
      event.bookUuid,
      event.recordUuid,
    );
  }

  final nextVersion = (baseNote?.version ?? 0) + 1;
  final canvasWidth = canvasSize?.width ?? baseNote?.canvasWidth;
  final canvasHeight = canvasSize?.height ?? baseNote?.canvasHeight;

  final mergedErasedStrokes = Map<String, List<String>>.from(
    baseNote?.erasedStrokesByEvent ?? const {},
  );
  for (final entry in erasedStrokesByEvent.entries) {
    final existingList = mergedErasedStrokes[entry.key] ?? const <String>[];
    final merged = <String>[...existingList];
    for (final id in entry.value) {
      if (!merged.contains(id)) {
        merged.add(id);
      }
    }
    mergedErasedStrokes[entry.key] = merged;
  }

  final noteToSave = Note(
    recordUuid: event.recordUuid,
    pages: pages,
    erasedStrokesByEvent: mergedErasedStrokes,
    canvasWidth: canvasWidth,
    canvasHeight: canvasHeight,
    createdAt:
        baseNote?.createdAt ?? localStateNote?.createdAt ?? DateTime.now(),
    updatedAt: DateTime.now(),
    version: nextVersion,
  );

  return adapter.saveNote(event.id!, noteToSave);
}

Future<List<int>> _measureIterations(
  int iterations,
  Future<void> Function() operation,
) async {
  final values = <int>[];
  for (var i = 0; i < iterations; i++) {
    final sw = Stopwatch()..start();
    await operation();
    sw.stop();
    values.add(sw.elapsedMicroseconds);
  }
  return values;
}

Map<String, num> _stats(List<int> microseconds) {
  final sorted = List<int>.from(microseconds)..sort();
  final total = microseconds.fold<int>(0, (sum, value) => sum + value);
  int percentile(double p) {
    final idx = ((sorted.length - 1) * p).round();
    return sorted[idx];
  }

  double toMs(num micros) => micros / 1000.0;

  return {
    'count': microseconds.length,
    'avg_ms': toMs(total / microseconds.length),
    'p50_ms': toMs(percentile(0.50)),
    'p95_ms': toMs(percentile(0.95)),
    'min_ms': toMs(sorted.first),
    'max_ms': toMs(sorted.last),
  };
}

void main() {
  test('event detail note save latency benchmark', () async {
    final dbService = PRDDatabaseService();
    final contentService = ContentService(_NoopApiClient(), dbService);
    const fetchDelay = Duration(milliseconds: 25);
    const saveDelay = Duration(milliseconds: 35);
    const warmupIterations = 3;
    const measureIterationsCount = 12;

    final createEvent = _buildEvent(
      eventId: 'event-create-bench',
      recordUuid: 'record-create-bench',
    );
    final createPages = _buildPages(createEvent.id!);

    final existingNote = Note(
      recordUuid: 'record-update-bench',
      pages: _buildPages('event-update-bench-base'),
      createdAt: DateTime.utc(2026, 3, 2, 8),
      updatedAt: DateTime.utc(2026, 3, 2, 8),
      version: 4,
    );
    final updateEvent = _buildEvent(
      eventId: 'event-update-bench',
      recordUuid: 'record-update-bench',
    );
    final updatePages = _buildPages(updateEvent.id!);

    Future<void> runLegacyCreate() async {
      final adapter = _DelayedNoteSyncAdapter(
        contentService,
        fetchDelay: fetchDelay,
        saveDelay: saveDelay,
      );
      adapter.serverNote = null;
      await _legacySaveNoteToServer(
        adapter: adapter,
        event: createEvent,
        pages: createPages,
        localStateNote: null,
      );
    }

    Future<void> runOptimizedCreate() async {
      final adapter = _DelayedNoteSyncAdapter(
        contentService,
        fetchDelay: fetchDelay,
        saveDelay: saveDelay,
      );
      final controller = EventDetailController(
        event: createEvent,
        isNew: true,
        dbService: dbService,
        onStateChanged: (_) {},
        contentService: contentService,
        noteSyncAdapter: adapter,
      );
      await controller.saveNoteToServer(
        createEvent.id!,
        createPages,
        eventDataOverride: createEvent,
      );
    }

    Future<void> runLegacyUpdate() async {
      final adapter = _DelayedNoteSyncAdapter(
        contentService,
        fetchDelay: fetchDelay,
        saveDelay: saveDelay,
      );
      adapter.serverNote = existingNote;
      await _legacySaveNoteToServer(
        adapter: adapter,
        event: updateEvent,
        pages: updatePages,
        localStateNote: existingNote,
      );
    }

    Future<void> runOptimizedUpdate() async {
      final adapter = _DelayedNoteSyncAdapter(
        contentService,
        fetchDelay: fetchDelay,
        saveDelay: saveDelay,
      );
      final controller = EventDetailController(
        event: updateEvent,
        isNew: false,
        dbService: dbService,
        onStateChanged: (_) {},
        contentService: contentService,
        noteSyncAdapter: adapter,
      );
      await controller.loadExistingPersonNote(existingNote);
      await controller.saveNoteToServer(
        updateEvent.id!,
        updatePages,
        eventDataOverride: updateEvent,
      );
    }

    for (var i = 0; i < warmupIterations; i++) {
      await runLegacyCreate();
      await runOptimizedCreate();
      await runLegacyUpdate();
      await runOptimizedUpdate();
    }

    final legacyCreate = await _measureIterations(
      measureIterationsCount,
      runLegacyCreate,
    );
    final optimizedCreate = await _measureIterations(
      measureIterationsCount,
      runOptimizedCreate,
    );
    final legacyUpdate = await _measureIterations(
      measureIterationsCount,
      runLegacyUpdate,
    );
    final optimizedUpdate = await _measureIterations(
      measureIterationsCount,
      runOptimizedUpdate,
    );

    final result = {
      'benchmark': 'event_detail_note_save_latency',
      'delays': {
        'prefetch_ms': fetchDelay.inMilliseconds,
        'save_ms': saveDelay.inMilliseconds,
      },
      'create_note_before': _stats(legacyCreate),
      'create_note_after': _stats(optimizedCreate),
      'update_note_before': _stats(legacyUpdate),
      'update_note_after': _stats(optimizedUpdate),
      'improvement_ms': {
        'create_avg_ms':
            (_stats(legacyCreate)['avg_ms']! -
                    _stats(optimizedCreate)['avg_ms']!)
                .toDouble(),
        'update_avg_ms':
            (_stats(legacyUpdate)['avg_ms']! -
                    _stats(optimizedUpdate)['avg_ms']!)
                .toDouble(),
      },
    };

    print(const JsonEncoder.withIndent('  ').convert(result));

    expect(
      (result['create_note_after'] as Map<String, num>)['avg_ms']!,
      lessThan((result['create_note_before'] as Map<String, num>)['avg_ms']!),
    );
    expect(
      (result['update_note_after'] as Map<String, num>)['avg_ms']!,
      lessThan((result['update_note_before'] as Map<String, num>)['avg_ms']!),
    );
  });
}
