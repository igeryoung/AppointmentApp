@Tags(['widget'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/l10n/app_localizations.dart';
import 'package:schedule_note_app/models/book.dart';
import 'package:schedule_note_app/screens/book_list/adapters/book_order_adapter.dart';
import 'package:schedule_note_app/screens/book_list/adapters/book_repository.dart';
import 'package:schedule_note_app/screens/book_list/adapters/device_registration_adapter.dart';
import 'package:schedule_note_app/screens/book_list/adapters/server_config_adapter.dart';
import 'package:schedule_note_app/screens/book_list/book_list_controller.dart';
import 'package:schedule_note_app/services/api_client.dart';

class _FakeBookRepository implements BookRepository {
  Object? pullError;

  @override
  Future<void> archive(String bookUuid) async {}

  @override
  Future<void> create(String name, {required String password}) async {}

  @override
  Future<void> delete(String bookUuid) async {}

  @override
  Future<List<Book>> getAll() async => const [];

  @override
  Future<Book?> getByName(String name) async => null;

  @override
  Future<Book?> getByUuid(String bookUuid) async => null;

  @override
  Future<List<Map<String, dynamic>>> listServerBooks({
    String? searchQuery,
  }) async {
    return const [
      {
        'bookUuid': 'server-book-1',
        'name': 'Server Book 1',
        'createdAt': '2026-02-28T12:00:00Z',
      },
    ];
  }

  @override
  Future<void> pullBookFromServer(
    String bookUuid, {
    required String password,
    bool lightImport = false,
  }) async {
    if (pullError != null) {
      throw pullError!;
    }
  }

  @override
  Future<void> update(Book book) async {}
}

class _FakeBookOrderAdapter implements BookOrderAdapter {
  @override
  List<Book> applyOrder(List<Book> books, List<String> savedOrder) => books;

  @override
  Future<List<String>> loadOrder() async => const [];

  @override
  Future<void> saveCurrentOrder(List<Book> books) async {}
}

class _FakeServerConfigAdapter implements ServerConfigAdapter {
  @override
  Future<String?> getUrl() async => null;

  @override
  Future<String> getUrlOrDefault() async => 'http://localhost:8080';

  @override
  Future<void> setUrl(String url) async {}
}

class _FakeDeviceRegistrationAdapter implements DeviceRegistrationAdapter {
  @override
  Future<Map<String, dynamic>?> getCredentials() async {
    return const {
      'deviceId': 'device-1',
      'deviceToken': 'token-1',
      'accountId': 'account-1',
      'username': 'user-1',
      'deviceRole': 'write',
      'isReadOnly': false,
    };
  }

  @override
  Future<bool> isRegistered() async => true;

  @override
  Future<void> logout() async {}

  @override
  Future<void> refreshDeviceRoleFromServer() async {}

  @override
  Future<void> authenticateAccount({
    required String baseUrl,
    required String username,
    required String password,
    String? registrationPassword,
    bool createAccount = false,
    String? deviceName,
    String? platform,
  }) async {}
}

Widget _buildLocalizedApp(Widget home) {
  return MaterialApp(
    onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('zh', ''), Locale('zh', 'TW')],
    locale: const Locale('zh', 'TW'),
    home: home,
  );
}

class _ImportHost extends StatelessWidget {
  final BookListController controller;

  const _ImportHost({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () => controller.openImportFromServerFlow(context),
              child: const Text('Import'),
            );
          },
        ),
      ),
    );
  }
}

void main() {
  Future<void> startImportFlow(WidgetTester tester) async {
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(find.text('Import Book from Server'), findsOneWidget);
    await tester.tap(find.text('Server Book 1'));
    await tester.pumpAndSettle();

    expect(find.text('Enter Book Password'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'wrong-password');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'BOOK-WIDGET-001: wrong password during import shows dedicated popup',
    (tester) async {
      final fakeRepo = _FakeBookRepository()
        ..pullError = ApiException(
          'Invalid book password',
          statusCode: 403,
          responseBody: '{"error":"INVALID_BOOK_PASSWORD"}',
        );
      final controller = BookListController(
        repo: fakeRepo,
        order: _FakeBookOrderAdapter(),
        serverConfig: _FakeServerConfigAdapter(),
        deviceReg: _FakeDeviceRegistrationAdapter(),
      );

      await tester.pumpWidget(
        _buildLocalizedApp(_ImportHost(controller: controller)),
      );

      await startImportFlow(tester);

      expect(find.text('密碼錯誤'), findsOneWidget);
      expect(find.text('您輸入的簿冊密碼不正確，請重新輸入後再試一次。'), findsOneWidget);
      expect(find.textContaining('403'), findsNothing);
    },
  );

  testWidgets(
    'BOOK-WIDGET-002: importing existing local book shows dedicated popup',
    (tester) async {
      final fakeRepo = _FakeBookRepository()
        ..pullError = Exception(
          'Book already exists locally. Cannot pull book that already exists.',
        );
      final controller = BookListController(
        repo: fakeRepo,
        order: _FakeBookOrderAdapter(),
        serverConfig: _FakeServerConfigAdapter(),
        deviceReg: _FakeDeviceRegistrationAdapter(),
      );

      await tester.pumpWidget(
        _buildLocalizedApp(_ImportHost(controller: controller)),
      );

      await startImportFlow(tester);

      expect(find.text('簿冊已存在'), findsOneWidget);
      expect(find.text('此簿冊已在本機，無法重複匯入。'), findsOneWidget);
      expect(find.textContaining('already exists'), findsNothing);
    },
  );
}
