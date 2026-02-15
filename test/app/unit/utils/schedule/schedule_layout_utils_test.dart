@Tags(['drawing', 'unit'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/models/schedule_drawing.dart';
import 'package:schedule_note_app/utils/schedule/schedule_layout_utils.dart';

void main() {
  test(
    'SCHEDULE-UTIL-001: getEffectiveDate() uses 2-day window in 2-day mode',
    () {
      // 2000-01-05 is a known split case:
      // - 2-day window start: 2000-01-05
      // - 3-day window start: 2000-01-04
      final selectedDate = DateTime(2000, 1, 5);

      final effective2Day = ScheduleLayoutUtils.getEffectiveDate(
        selectedDate,
        viewMode: ScheduleDrawing.VIEW_MODE_2DAY,
      );
      final effective3Day = ScheduleLayoutUtils.getEffectiveDate(selectedDate);

      expect(effective2Day, DateTime(2000, 1, 5));
      expect(effective3Day, DateTime(2000, 1, 4));
    },
  );

  test(
    'SCHEDULE-UTIL-002: getPageId() isolates 2-day pages from previous page and 3-day mode',
    () {
      final twoDayCurrent = ScheduleLayoutUtils.getPageId(
        DateTime(2000, 1, 5),
        viewMode: ScheduleDrawing.VIEW_MODE_2DAY,
      );
      final twoDaySameWindow = ScheduleLayoutUtils.getPageId(
        DateTime(2000, 1, 6),
        viewMode: ScheduleDrawing.VIEW_MODE_2DAY,
      );
      final twoDayPreviousWindow = ScheduleLayoutUtils.getPageId(
        DateTime(2000, 1, 4),
        viewMode: ScheduleDrawing.VIEW_MODE_2DAY,
      );
      final threeDayForSameDate = ScheduleLayoutUtils.getPageId(
        DateTime(2000, 1, 5),
        viewMode: ScheduleDrawing.VIEW_MODE_3DAY,
      );

      expect(twoDayCurrent, twoDaySameWindow);
      expect(twoDayCurrent, isNot(twoDayPreviousWindow));
      expect(twoDayCurrent, isNot(threeDayForSameDate));
    },
  );
}
