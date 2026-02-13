@Tags(['book', 'unit'])
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:schedule_note_app/services/book_order_service.dart';

import '../../../support/fixtures/book_fixtures.dart';

void main() {
  late BookOrderService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = BookOrderService();
  });

  test(
    'BOOK-UNIT-005: applyOrder() keeps original order when no saved order exists',
    () {
      // Arrange
      final books = [
        makeBook(uuid: 'book-1', name: 'Book 1'),
        makeBook(uuid: 'book-2', name: 'Book 2'),
      ];

      // Act
      final result = service.applyOrder(books, []);

      // Assert
      expect(result.map((b) => b.uuid).toList(), ['book-1', 'book-2']);
    },
  );

  test(
    'BOOK-UNIT-005: applyOrder() puts unsaved books first then applies saved order',
    () {
      // Arrange
      final books = [
        makeBook(uuid: 'book-a', name: 'Book A'),
        makeBook(uuid: 'book-b', name: 'Book B'),
        makeBook(uuid: 'book-c', name: 'Book C'),
      ];
      final savedOrder = ['book-b', 'book-a'];

      // Act
      final result = service.applyOrder(books, savedOrder);

      // Assert
      expect(result.map((b) => b.uuid).toList(), [
        'book-c',
        'book-b',
        'book-a',
      ]);
    },
  );

  test(
    'BOOK-UNIT-005: saveCurrentOrder() persists UUID order for later load',
    () async {
      // Arrange
      final books = [
        makeBook(uuid: 'book-z', name: 'Book Z'),
        makeBook(uuid: 'book-x', name: 'Book X'),
      ];

      // Act
      await service.saveCurrentOrder(books);
      final loaded = await service.loadBookOrder();

      // Assert
      expect(loaded, ['book-z', 'book-x']);
    },
  );
}
