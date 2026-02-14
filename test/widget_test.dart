import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/app.dart';

void main() {
  testWidgets('APP-WIDGET-001: ScheduleNoteApp builds', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ScheduleNoteApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
