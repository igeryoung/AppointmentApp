@Tags(['benchmark', 'event'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/models/charge_item.dart';
import 'package:schedule_note_app/models/event.dart';
import 'package:schedule_note_app/models/event_type.dart';
import 'package:schedule_note_app/screens/event_detail/event_detail_controller.dart';
import 'package:schedule_note_app/services/api_client.dart';
import 'package:schedule_note_app/services/content_service.dart';
import 'package:schedule_note_app/services/database/prd_database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/db_seed.dart';
import '../support/fixtures/event_fixtures.dart';
import '../support/test_db_path.dart';

const _benchBookUuid = 'book-bench';
const _benchEventId = '11111111-1111-4111-8111-111111111111';
const _benchRecordUuid = '22222222-2222-4222-8222-222222222222';

List<ChargeItemPayment> _singlePaidItem(int amount, DateTime paidDate) {
  return [
    ChargeItemPayment(
      id: 'payment-$amount-${paidDate.millisecondsSinceEpoch}',
      amount: amount,
      paidDate: paidDate,
    ),
  ];
}

class _DelayedChargeItemApiClient extends ApiClient {
  _DelayedChargeItemApiClient({required this.saveDelay})
    : super(baseUrl: 'http://benchmark.local');

  final Duration saveDelay;

  @override
  Future<Map<String, dynamic>> saveChargeItem({
    required String recordUuid,
    required Map<String, dynamic> chargeItemData,
    required String deviceId,
    required String deviceToken,
  }) async {
    await Future<void>.delayed(saveDelay);
    final nowIso = DateTime.now().toUtc().toIso8601String();
    return {
      ...chargeItemData,
      'id': chargeItemData['id'],
      'record_uuid': recordUuid,
      'event_id': chargeItemData['eventId'],
      'item_name': chargeItemData['itemName'],
      'item_price': chargeItemData['itemPrice'],
      'received_amount': chargeItemData['receivedAmount'],
      'paidItems': chargeItemData['paidItems'] ?? const [],
      'paid_items_json': jsonEncode(chargeItemData['paidItems'] ?? const []),
      'created_at': chargeItemData['createdAt'] ?? nowIso,
      'updated_at': nowIso,
      'version': chargeItemData['version'] ?? 1,
      'is_deleted': chargeItemData['isDeleted'] == true,
    };
  }
}

class _ScenarioSample {
  const _ScenarioSample({
    required this.userVisibleMicros,
    required this.localWriteMicros,
    required this.serverSyncMicros,
    required this.reloadMicros,
    required this.backgroundMicros,
    required this.totalMicros,
  });

  final int userVisibleMicros;
  final int localWriteMicros;
  final int serverSyncMicros;
  final int reloadMicros;
  final int backgroundMicros;
  final int totalMicros;
}

Map<String, num> _stats(List<int> microseconds) {
  final sorted = List<int>.from(microseconds)..sort();
  final total = microseconds.fold<int>(0, (sum, value) => sum + value);

  int percentile(double p) {
    final index = ((sorted.length - 1) * p).round();
    return sorted[index];
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

Map<String, Map<String, num>> _sampleStats(List<_ScenarioSample> samples) {
  List<int> pick(int Function(_ScenarioSample sample) selector) =>
      samples.map(selector).toList(growable: false);

  return {
    'user_visible_ms': _stats(pick((sample) => sample.userVisibleMicros)),
    'local_write_ms': _stats(pick((sample) => sample.localWriteMicros)),
    'server_sync_ms': _stats(pick((sample) => sample.serverSyncMicros)),
    'reload_ms': _stats(pick((sample) => sample.reloadMicros)),
    'background_ms': _stats(pick((sample) => sample.backgroundMicros)),
    'total_ms': _stats(pick((sample) => sample.totalMicros)),
  };
}

Future<void> _waitForSyncedChargeItem(
  PRDDatabaseService dbService,
  String itemId,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    final item = await dbService.getChargeItemById(itemId);
    if (item != null && !item.isDirty) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Timed out waiting for synced charge item $itemId');
}

Future<void> _resetChargeItems(PRDDatabaseService dbService) async {
  final db = await dbService.database;
  await db.delete('charge_items');
  await db.update('events', {'has_charge_items': 0});
}

Event _buildBenchEvent() {
  return makeEvent(
    id: _benchEventId,
    bookUuid: _benchBookUuid,
    recordUuid: _benchRecordUuid,
    title: 'Bench User',
    recordNumber: 'BENCH-001',
    eventTypes: const [EventType.consultation],
  );
}

ChargeItem _newChargeItem() {
  return ChargeItem(
    recordUuid: 'ignored-by-controller',
    itemName: 'Bench MRI',
    itemPrice: 2600,
  );
}

ChargeItem _existingChargeItem() {
  return ChargeItem(
    id: 'charge-bench-existing',
    recordUuid: _benchRecordUuid,
    eventId: _benchEventId,
    itemName: 'Bench Medication',
    itemPrice: 800,
    receivedAmount: 100,
    paidItems: _singlePaidItem(100, DateTime(2026, 3, 20)),
  );
}

Future<_ScenarioSample> _runLegacyAdd(
  PRDDatabaseService dbService,
  ContentService contentService,
) async {
  await _resetChargeItems(dbService);

  final newItem = _newChargeItem().copyWith(
    recordUuid: _benchRecordUuid,
    eventId: _benchEventId,
  );

  final total = Stopwatch()..start();

  final localWrite = Stopwatch()..start();
  final savedItem = await dbService.saveChargeItem(newItem);
  localWrite.stop();

  final serverSync = Stopwatch()..start();
  final serverItem = await contentService.apiClient.saveChargeItem(
    recordUuid: savedItem.recordUuid,
    chargeItemData: {...savedItem.toServerMap(), 'bookUuid': _benchBookUuid},
    deviceId: 'device-bench',
    deviceToken: 'token-bench',
  );
  await dbService.applyServerChargeItemChange(serverItem);
  serverSync.stop();

  final reload = Stopwatch()..start();
  await dbService.getChargeItemsByRecordUuid(_benchRecordUuid);
  reload.stop();

  total.stop();

  return _ScenarioSample(
    userVisibleMicros: total.elapsedMicroseconds,
    localWriteMicros: localWrite.elapsedMicroseconds,
    serverSyncMicros: serverSync.elapsedMicroseconds,
    reloadMicros: reload.elapsedMicroseconds,
    backgroundMicros: 0,
    totalMicros: total.elapsedMicroseconds,
  );
}

Future<_ScenarioSample> _runOptimizedAdd(
  PRDDatabaseService dbService,
  ContentService contentService,
  Event event,
) async {
  await _resetChargeItems(dbService);

  final controller = EventDetailController(
    event: event,
    isNew: false,
    dbService: dbService,
    onStateChanged: (_) {},
    contentService: contentService,
  );

  final total = Stopwatch()..start();
  await controller.addChargeItem(_newChargeItem());
  final userVisibleMicros = total.elapsedMicroseconds;
  final itemId = controller.state.chargeItems.single.id;

  await _waitForSyncedChargeItem(dbService, itemId);
  total.stop();

  return _ScenarioSample(
    userVisibleMicros: userVisibleMicros,
    localWriteMicros: userVisibleMicros,
    serverSyncMicros: 0,
    reloadMicros: 0,
    backgroundMicros: total.elapsedMicroseconds - userVisibleMicros,
    totalMicros: total.elapsedMicroseconds,
  );
}

Future<_ScenarioSample> _runLegacyEdit(
  PRDDatabaseService dbService,
  ContentService contentService,
) async {
  await _resetChargeItems(dbService);
  final existing = _existingChargeItem();
  await dbService.saveChargeItem(existing);
  final updated = existing.copyWith(
    receivedAmount: 500,
    paidItems: _singlePaidItem(500, DateTime(2026, 3, 21)),
  );

  final total = Stopwatch()..start();

  final localWrite = Stopwatch()..start();
  final savedItem = await dbService.saveChargeItem(updated);
  localWrite.stop();

  final serverSync = Stopwatch()..start();
  final serverItem = await contentService.apiClient.saveChargeItem(
    recordUuid: savedItem.recordUuid,
    chargeItemData: {...savedItem.toServerMap(), 'bookUuid': _benchBookUuid},
    deviceId: 'device-bench',
    deviceToken: 'token-bench',
  );
  await dbService.applyServerChargeItemChange(serverItem);
  serverSync.stop();

  final reload = Stopwatch()..start();
  await dbService.getChargeItemsByRecordUuid(_benchRecordUuid);
  reload.stop();

  total.stop();

  return _ScenarioSample(
    userVisibleMicros: total.elapsedMicroseconds,
    localWriteMicros: localWrite.elapsedMicroseconds,
    serverSyncMicros: serverSync.elapsedMicroseconds,
    reloadMicros: reload.elapsedMicroseconds,
    backgroundMicros: 0,
    totalMicros: total.elapsedMicroseconds,
  );
}

Future<_ScenarioSample> _runOptimizedEdit(
  PRDDatabaseService dbService,
  ContentService contentService,
  Event event,
) async {
  await _resetChargeItems(dbService);
  final existing = _existingChargeItem();
  await dbService.saveChargeItem(existing);

  final controller = EventDetailController(
    event: event,
    isNew: false,
    dbService: dbService,
    onStateChanged: (_) {},
    contentService: contentService,
  );
  await controller.loadChargeItems();

  final total = Stopwatch()..start();
  await controller.editChargeItem(
    existing.copyWith(
      receivedAmount: 500,
      paidItems: _singlePaidItem(500, DateTime(2026, 3, 21)),
    ),
  );
  final userVisibleMicros = total.elapsedMicroseconds;

  await _waitForSyncedChargeItem(dbService, existing.id);
  total.stop();

  return _ScenarioSample(
    userVisibleMicros: userVisibleMicros,
    localWriteMicros: userVisibleMicros,
    serverSyncMicros: 0,
    reloadMicros: 0,
    backgroundMicros: total.elapsedMicroseconds - userVisibleMicros,
    totalMicros: total.elapsedMicroseconds,
  );
}

void main() {
  test('charge item latency benchmark', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await setUniqueDatabasePath('charge_item_latency_benchmark');

    final dbService = PRDDatabaseService();
    await dbService.clearAllData();
    final db = await dbService.database;
    final event = _buildBenchEvent();

    await seedBook(db, bookUuid: _benchBookUuid);
    await seedRecord(
      db,
      recordUuid: _benchRecordUuid,
      name: 'Bench User',
      recordNumber: 'BENCH-001',
    );
    await seedEvent(db, event: event);
    await dbService.saveDeviceCredentials(
      deviceId: 'device-bench',
      deviceToken: 'token-bench',
      deviceName: 'Benchmark Device',
      serverUrl: 'http://benchmark.local',
      platform: 'benchmark',
    );

    const saveDelay = Duration(milliseconds: 40);
    const warmupIterations = 3;
    const measureIterations = 12;

    final contentService = ContentService(
      _DelayedChargeItemApiClient(saveDelay: saveDelay),
      dbService,
    );

    for (var i = 0; i < warmupIterations; i++) {
      await _runLegacyAdd(dbService, contentService);
      await _runOptimizedAdd(dbService, contentService, event);
      await _runLegacyEdit(dbService, contentService);
      await _runOptimizedEdit(dbService, contentService, event);
    }

    final legacyAddSamples = <_ScenarioSample>[];
    final optimizedAddSamples = <_ScenarioSample>[];
    final legacyEditSamples = <_ScenarioSample>[];
    final optimizedEditSamples = <_ScenarioSample>[];

    for (var i = 0; i < measureIterations; i++) {
      legacyAddSamples.add(await _runLegacyAdd(dbService, contentService));
      optimizedAddSamples.add(
        await _runOptimizedAdd(dbService, contentService, event),
      );
      legacyEditSamples.add(await _runLegacyEdit(dbService, contentService));
      optimizedEditSamples.add(
        await _runOptimizedEdit(dbService, contentService, event),
      );
    }

    final result = {
      'benchmark': 'charge_item_latency',
      'delays': {'server_save_ms': saveDelay.inMilliseconds},
      'add_before': _sampleStats(legacyAddSamples),
      'add_after': _sampleStats(optimizedAddSamples),
      'edit_before': _sampleStats(legacyEditSamples),
      'edit_after': _sampleStats(optimizedEditSamples),
      'improvement_ms': {
        'add_user_visible_avg_ms':
            (_sampleStats(legacyAddSamples)['user_visible_ms']!['avg_ms']! -
                    _sampleStats(
                      optimizedAddSamples,
                    )['user_visible_ms']!['avg_ms']!)
                .toDouble(),
        'edit_user_visible_avg_ms':
            (_sampleStats(legacyEditSamples)['user_visible_ms']!['avg_ms']! -
                    _sampleStats(
                      optimizedEditSamples,
                    )['user_visible_ms']!['avg_ms']!)
                .toDouble(),
      },
    };
    final addBefore = result['add_before']! as Map<String, Map<String, num>>;
    final addAfter = result['add_after']! as Map<String, Map<String, num>>;
    final editBefore = result['edit_before']! as Map<String, Map<String, num>>;
    final editAfter = result['edit_after']! as Map<String, Map<String, num>>;

    print(const JsonEncoder.withIndent('  ').convert(result));

    expect(
      addAfter['user_visible_ms']!['avg_ms']!,
      lessThan(addBefore['user_visible_ms']!['avg_ms']!),
    );
    expect(
      editAfter['user_visible_ms']!['avg_ms']!,
      lessThan(editBefore['user_visible_ms']!['avg_ms']!),
    );

    await dbService.close();
    PRDDatabaseService.resetInstance();
  });
}
