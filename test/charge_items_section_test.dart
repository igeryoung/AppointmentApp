import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:schedule_note_app/l10n/app_localizations.dart';
import 'package:schedule_note_app/models/charge_item.dart';
import 'package:schedule_note_app/models/event.dart';
import 'package:schedule_note_app/models/event_type.dart';
import 'package:schedule_note_app/screens/event_detail/event_detail_controller.dart';
import 'package:schedule_note_app/screens/event_detail/event_detail_state.dart';
import 'package:schedule_note_app/screens/event_detail/widgets/charge_items_section.dart';
import 'package:schedule_note_app/services/database_service_interface.dart';

// Mock controller for testing
class MockEventDetailController extends Mock implements EventDetailController {
  @override
  Future<void> addChargeItem(ChargeItem item, {bool associateWithEvent = false}) async {}

  @override
  Future<void> editChargeItem(ChargeItem item) async {}

  @override
  Future<void> deleteChargeItem(ChargeItem item) async {}

  @override
  Future<void> toggleChargeItemPaidStatus(ChargeItem item) async {}

  @override
  Future<void> toggleChargeItemsFilter() async {}
}

void main() {
  testWidgets('add dialog can be opened and closed without crashing', (tester) async {
    await tester.pumpWidget(const _ChargeItemsSectionHarness());

    // Expand the section to show the overlay.
    await tester.tap(find.text('Charge Items').first);
    await tester.pumpAndSettle();

    // Open the add dialog.
    await tester.tap(find.text('Add Charge Item'));
    await tester.pumpAndSettle();

    // Close the dialog without saving. The overlay should reopen automatically.
    await tester.tap(find.text('Cancel'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Add Charge Item'), findsOneWidget);

    // Close the overlay by tapping outside of it.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
  });
}

class _ChargeItemsSectionHarness extends StatefulWidget {
  const _ChargeItemsSectionHarness();

  @override
  State<_ChargeItemsSectionHarness> createState() => _ChargeItemsSectionHarnessState();
}

class _ChargeItemsSectionHarnessState extends State<_ChargeItemsSectionHarness> {
  final List<ChargeItem> _items = const [];
  final MockEventDetailController _controller = MockEventDetailController();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(8),
          child: ChargeItemsSection(
            chargeItems: _items,
            controller: _controller,
            hasRecordUuid: true,
            showOnlyThisEventItems: false,
          ),
        ),
      ),
    );
  }
}
