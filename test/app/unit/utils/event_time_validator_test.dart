@Tags(['unit'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/utils/event_time_validator.dart';

void main() {
  test(
    'EVENT-TIME-UNIT-001: start times stop before 20:00 while end times may equal 20:00',
    () {
      final validStart = DateTime(2026, 3, 25, 19, 45);
      final invalidStart = DateTime(2026, 3, 25, 20, 0);
      final validEnd = DateTime(2026, 3, 25, 20, 0);
      final invalidEnd = DateTime(2026, 3, 25, 20, 15);

      expect(EventTimeValidator.validateStartTime(validStart), isNull);
      expect(EventTimeValidator.validateStartTime(invalidStart), isNotNull);
      expect(EventTimeValidator.validateEndTime(validEnd), isNull);
      expect(EventTimeValidator.validateEndTime(invalidEnd), isNotNull);
    },
  );

  test(
    'EVENT-TIME-UNIT-002: latest allowed bounds track the 20:00 schedule cutoff',
    () {
      final date = DateTime(2026, 3, 25);

      expect(
        EventTimeValidator.getLatestStartTime(date),
        DateTime(2026, 3, 25, 19, 45),
      );
      expect(
        EventTimeValidator.getLatestEndTime(date),
        DateTime(2026, 3, 25, 20, 0),
      );
      expect(
        EventTimeValidator.getMaxDurationMinutes(DateTime(2026, 3, 25, 19, 30)),
        30,
      );
    },
  );
}
