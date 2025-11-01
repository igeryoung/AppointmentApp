import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/models/book.dart';
import 'package:schedule_note_app/repositories/book_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Unit tests for BookRepositoryImpl
/// These tests verify the repository works independently of PRDDatabaseService
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('BookRepositoryImpl', () {
    late Database testDb;
    late BookRepositoryImpl repository;

    setUp(() async {
      // Create an in-memory database for testing
      testDb = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            // Create books table
            await db.execute('''
              CREATE TABLE books (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                book_uuid TEXT NOT NULL UNIQUE,
                created_at INTEGER NOT NULL,
                archived_at INTEGER
              )
            ''');
          },
        ),
      );

      repository = BookRepositoryImpl(() async => testDb);
    });

    tearDown(() async {
      await testDb.close();
    });

    test('create → getById → returns created book', () async {
      final book = await repository.create('Test Book');

      expect(book.id, isNotNull);
      expect(book.name, 'Test Book');
      expect(book.uuid, isNotNull);

      final retrieved = await repository.getById(book.id!);
      expect(retrieved, isNotNull);
      expect(retrieved!.id, book.id);
      expect(retrieved.name, book.name);
      expect(retrieved.uuid, book.uuid);
    });

    test('create multiple books → getAll → returns all books', () async {
      await repository.create('Book 1');
      await repository.create('Book 2');
      await repository.create('Book 3');

      final books = await repository.getAll();
      expect(books.length, 3);
      // Verify all books are present (order may vary by created_at)
      final names = books.map((b) => b.name).toSet();
      expect(names.contains('Book 1'), true);
      expect(names.contains('Book 2'), true);
      expect(names.contains('Book 3'), true);
    });

    test('update book → changes persist', () async {
      final book = await repository.create('Original Name');
      final updatedBook = book.copyWith(name: 'Updated Name');

      await repository.update(updatedBook);

      final retrieved = await repository.getById(book.id!);
      expect(retrieved!.name, 'Updated Name');
    });

    test('delete book → book removed', () async {
      final book = await repository.create('To Delete');

      await repository.delete(book.id!);

      final retrieved = await repository.getById(book.id!);
      expect(retrieved, isNull);
    });

    test('archive book → book archived', () async {
      final book = await repository.create('To Archive');

      await repository.archive(book.id!);

      // Without includeArchived, should not appear
      final booksWithoutArchived = await repository.getAll(includeArchived: false);
      expect(booksWithoutArchived.length, 0);

      // With includeArchived, should appear
      final booksWithArchived = await repository.getAll(includeArchived: true);
      expect(booksWithArchived.length, 1);
      expect(booksWithArchived[0].isArchived, true);
    });

    test('create with empty name → throws ArgumentError', () async {
      expect(
        () => repository.create(''),
        throwsArgumentError,
      );
    });

    test('update with null ID → throws ArgumentError', () async {
      final book = Book(
        name: 'Test',
        createdAt: DateTime.now(),
      );

      expect(
        () => repository.update(book),
        throwsArgumentError,
      );
    });

    test('delete non-existent book → throws Exception', () async {
      expect(
        () => repository.delete(99999),
        throwsException,
      );
    });
  });
}
