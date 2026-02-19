@Tags(['integration', 'event'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'event_metadata/event_integ_001_metadata_update_test.dart';
import 'event_metadata/event_integ_002_no_record_reschedule_test.dart';
import 'event_metadata/event_integ_003_has_note_scope_test.dart';
import 'event_metadata/event_integ_004_refill_record_number_test.dart';
import 'event_metadata/event_integ_005_server_only_contract_test.dart';
import 'event_metadata/event_integ_007_book_contract_test.dart';
import 'event_metadata/event_integ_008_note_contract_test.dart';
import 'event_metadata/event_integ_009_drawing_contract_test.dart';
import 'event_metadata/event_integ_010_device_session_contract_test.dart';
import 'event_metadata/event_integ_011_multi_device_metadata_lww_test.dart';
import 'event_metadata/event_integ_012_multi_device_note_conflict_resolution_test.dart';
import 'event_metadata/live_server_test_support.dart';

void main() {
  final config = LiveServerConfig.fromEnv();

  registerEventInteg001(config: config);
  registerEventInteg002(config: config);
  registerEventInteg003(config: config);
  registerEventInteg004(config: config);
  registerEventInteg005(config: config);
  registerEventInteg007(config: config);
  registerEventInteg008(config: config);
  registerEventInteg009(config: config);
  registerEventInteg010(config: config);
  registerEventInteg011(config: config);
  registerEventInteg012(config: config);
}
