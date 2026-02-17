import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/models/note.dart';
import 'package:schedule_note_app/widgets/handwriting_canvas.dart';

void main() {
  group('HandwritingPainter focus mode', () {
    const currentEventId = 'event-current';
    final currentStroke = Stroke(
      eventUuid: currentEventId,
      points: const [StrokePoint(10, 10)],
      color: 0xFF336699,
    );
    final otherEventStroke = Stroke(
      eventUuid: 'event-other',
      points: const [StrokePoint(20, 20)],
      color: 0xFF112233,
    );
    final unlinkedStroke = Stroke(
      points: const [StrokePoint(30, 30)],
      color: 0x66112233,
    );

    test(
      'marks non-current event strokes as gray candidates in focus mode',
      () {
        expect(
          HandwritingPainter.shouldGrayOutStroke(
            stroke: otherEventStroke,
            showOnlyCurrentEvent: true,
            currentEventUuid: currentEventId,
          ),
          isTrue,
        );
      },
    );

    test('keeps current event strokes fully colored in focus mode', () {
      expect(
        HandwritingPainter.shouldGrayOutStroke(
          stroke: currentStroke,
          showOnlyCurrentEvent: true,
          currentEventUuid: currentEventId,
        ),
        isFalse,
      );
    });

    test('keeps all strokes fully colored when focus mode is off', () {
      expect(
        HandwritingPainter.shouldGrayOutStroke(
          stroke: otherEventStroke,
          showOnlyCurrentEvent: false,
          currentEventUuid: currentEventId,
        ),
        isFalse,
      );
    });

    test('uses original stroke color when gray-out is disabled', () {
      final resolved = HandwritingPainter.resolveStrokeColor(
        stroke: currentStroke,
        grayOut: false,
      );

      expect(resolved, const Color(0xFF336699));
    });

    test('maps gray-out color to shallow gray with bounded opacity', () {
      final resolvedOpaque = HandwritingPainter.resolveStrokeColor(
        stroke: otherEventStroke,
        grayOut: true,
      );
      final resolvedVeryLight = HandwritingPainter.resolveStrokeColor(
        stroke: unlinkedStroke.copyWith(color: 0x10112233),
        grayOut: true,
      );

      expect(resolvedOpaque.toARGB32() & 0x00FFFFFF, 0x00BDBDBD);
      expect(resolvedOpaque.a, closeTo(0.55, 0.001));

      expect(resolvedVeryLight.toARGB32() & 0x00FFFFFF, 0x00BDBDBD);
      expect(resolvedVeryLight.a, closeTo(0.28, 0.0001));
    });
  });
}
