@Tags(['integration', 'event'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'event_metadata/event_integ_001_metadata_update_test.dart';
import 'event_metadata/event_integ_002_no_record_reschedule_test.dart';
import 'event_metadata/event_integ_003_has_note_scope_test.dart';
import 'event_metadata/event_integ_004_refill_record_number_test.dart';
import 'event_metadata/live_server_test_support.dart';

void main() {
  final config = LiveServerConfig.fromEnv();

  registerEventInteg001(config: config);
  registerEventInteg002(config: config);
  registerEventInteg003(config: config);
  registerEventInteg004(config: config);
}
