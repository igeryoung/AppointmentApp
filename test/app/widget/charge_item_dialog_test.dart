@Tags(['widget'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/l10n/app_localizations.dart';
import 'package:schedule_note_app/models/charge_item.dart';
import 'package:schedule_note_app/widgets/dialogs/charge_item_dialog.dart';

Widget _buildLocalizedApp(Widget home) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh', 'TW'),
    home: home,
  );
}

class _ChargeItemDialogHost extends StatefulWidget {
  final ChargeItem existingItem;

  const _ChargeItemDialogHost({required this.existingItem});

  @override
  State<_ChargeItemDialogHost> createState() => _ChargeItemDialogHostState();
}

class _ChargeItemDialogHostState extends State<_ChargeItemDialogHost> {
  ChargeItem? _savedItem;

  Future<void> _openDialog() async {
    final result = await showDialog<ChargeItem>(
      context: context,
      builder: (context) => ChargeItemDialog(existingItem: widget.existingItem),
    );

    if (!mounted || result == null) {
      return;
    }

    setState(() {
      _savedItem = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton(onPressed: _openDialog, child: const Text('Open')),
          if (_savedItem != null)
            Text('saved:${_savedItem!.receivedAmount}:${_savedItem!.isPaid}'),
        ],
      ),
    );
  }
}

void main() {
  final existingItem = ChargeItem(
    id: 'charge-item-1',
    recordUuid: 'record-1',
    eventId: 'event-1',
    itemName: 'Consultation',
    itemPrice: 1000,
    receivedAmount: 250,
  );

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('編輯待收款項'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(3));
  }

  group('ChargeItemDialog partial payment editing', () {
    testWidgets(
      'CHARGE-ITEM-WIDGET-001: editing keeps partial paid amount instead of resetting it',
      (tester) async {
        await tester.pumpWidget(
          _buildLocalizedApp(
            _ChargeItemDialogHost(existingItem: existingItem),
          ),
        );

        await openDialog(tester);

        await tester.enterText(find.byType(TextFormField).at(2), '300');
        await tester.tap(find.text('儲存'));
        await tester.pumpAndSettle();

        expect(find.text('saved:300:false'), findsOneWidget);
      },
    );

    testWidgets(
      'CHARGE-ITEM-WIDGET-002: editing rejects paid amount greater than cost',
      (tester) async {
        await tester.pumpWidget(
          _buildLocalizedApp(
            _ChargeItemDialogHost(existingItem: existingItem),
          ),
        );

        await openDialog(tester);

        await tester.enterText(find.byType(TextFormField).at(2), '1200');
        await tester.tap(find.text('儲存'));
        await tester.pump();

        expect(find.text('已付金額不可超過費用'), findsOneWidget);
        expect(find.text('編輯待收款項'), findsOneWidget);
        expect(find.textContaining('saved:'), findsNothing);
      },
    );
  });
}
