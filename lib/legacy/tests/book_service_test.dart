import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:schedule_note_app/services/book_service.dart';
import 'package:schedule_note_app/services/database_service.dart';
import 'package:schedule_note_app/models/appointment.dart';

void main() {
  late BookService bookService;
  late DatabaseService databaseService;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    DatabaseService.resetInstance();
    databaseService = DatabaseService();
    bookService = BookService();
    await databaseService.clearAllData();
  });

  tearDown(() async {
    await databaseService.close();
    DatabaseService.resetInstance();
  });

  group('BookService - Basic Operations', () {
    test('should create book with valid name', () async {
      // Act
      final book = await bookService.createBook('Doctor A');

      // Assert
      expect(book.name, 'Doctor A');
      expect(book.id, isNotNull);
      expect(book.createdAt, isNotNull);
    });

    test('should get all books', () async {
      // Arrange
      await bookService.createBook('Book 1');
      await bookService.createBook('Book 2');

      // Act
      final books = await bookService.getBooks();

      // Assert
      expect(books.length, 2);
      final bookNames = books.map((b) => b.name).toSet();
      expect(bookNames.contains('Book 1'), isTrue);
      expect(bookNames.contains('Book 2'), isTrue);
    });

    test('should get book by id', () async {
      // Arrange
      final createdBook = await bookService.createBook('Test Book');

      // Act
      final retrievedBook = await bookService.getBookById(createdBook.id!);

      // Assert
      expect(retrievedBook, isNotNull);
      expect(retrievedBook!.id, createdBook.id);
      expect(retrievedBook.name, 'Test Book');
    });

    test('should return null for non-existent book', () async {
      // Act
      final book = await bookService.getBookById(999);

      // Assert
      expect(book, isNull);
    });

    test('should update book name', () async {
      // Arrange
      final book = await bookService.createBook('Original Name');

      // Act
      final updatedBook = await bookService.updateBookName(book.id!, 'Updated Name');

      // Assert
      expect(updatedBook.name, 'Updated Name');
      expect(updatedBook.id, book.id);
    });

    test('should delete book', () async {
      // Arrange
      final book = await bookService.createBook('Test Book');

      // Act
      await bookService.deleteBook(book.id!);

      // Assert
      final retrievedBook = await bookService.getBookById(book.id!);
      expect(retrievedBook, isNull);
    });
  });

  group('BookService - Validation Tests', () {
    test('should throw exception for empty book name', () async {
      // Act & Assert
      expect(
        () => bookService.createBook(''),
        throwsA(isA<BookServiceException>()),
      );

      expect(
        () => bookService.createBook('   '),
        throwsA(isA<BookServiceException>()),
      );
    });

    test('should throw exception for book name too long', () async {
      // Arrange
      final longName = 'A' * 51; // 51 characters

      // Act & Assert
      expect(
        () => bookService.createBook(longName),
        throwsA(isA<BookServiceException>()),
      );
    });

    test('should throw exception for duplicate book name', () async {
      // Arrange
      await bookService.createBook('Duplicate Name');

      // Act & Assert
      expect(
        () => bookService.createBook('Duplicate Name'),
        throwsA(isA<BookServiceException>()),
      );

      // Case insensitive check
      expect(
        () => bookService.createBook('duplicate name'),
        throwsA(isA<BookServiceException>()),
      );
    });

    test('should throw exception when updating to duplicate name', () async {
      // Arrange
      final book1 = await bookService.createBook('Book 1');
      final book2 = await bookService.createBook('Book 2');

      // Act & Assert
      expect(
        () => bookService.updateBookName(book1.id!, 'Book 2'),
        throwsA(isA<BookServiceException>()),
      );
    });

    test('should throw exception when updating non-existent book', () async {
      // Act & Assert
      expect(
        () => bookService.updateBookName(999, 'New Name'),
        throwsA(isA<BookServiceException>()),
      );
    });

    test('should throw exception when deleting non-existent book', () async {
      // Act & Assert
      expect(
        () => bookService.deleteBook(999),
        throwsA(isA<BookServiceException>()),
      );
    });

    test('should validate book name correctly', () async {
      // Test valid name
      var result = await bookService.validateBookName('Valid Name');
      expect(result.isValid, isTrue);
      expect(result.errorMessage, isNull);

      // Test empty name
      result = await bookService.validateBookName('');
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('不能为空'));

      // Test long name
      result = await bookService.validateBookName('A' * 51);
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('不能超过50个字符'));

      // Test duplicate name
      await bookService.createBook('Existing Name');
      result = await bookService.validateBookName('Existing Name');
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('已存在'));

      // Test duplicate name with exclusion
      final book = await bookService.createBook('Another Name');
      result = await bookService.validateBookName('Another Name', excludeId: book.id);
      expect(result.isValid, isTrue);
    });
  });

  group('BookService - Statistics', () {
    test('should get book statistics', () async {
      // Arrange
      final book = await bookService.createBook('Test Book');

      // Create some appointments
      final appointment1 = Appointment(
        bookId: book.id!,
        startTime: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final appointment2 = Appointment(
        bookId: book.id!,
        startTime: DateTime.now().add(const Duration(hours: 1)),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await databaseService.createAppointment(appointment1);
      await databaseService.createAppointment(appointment2);

      // Act
      final statistics = await bookService.getBookStatistics(book.id!);

      // Assert
      expect(statistics.book.id, book.id);
      expect(statistics.book.name, 'Test Book');
      expect(statistics.totalAppointments, 2);
    });

    test('should throw exception for non-existent book statistics', () async {
      // Act & Assert
      expect(
        () => bookService.getBookStatistics(999),
        throwsA(isA<BookServiceException>()),
      );
    });
  });

  group('BookService - Edge Cases', () {
    test('should trim whitespace from book names', () async {
      // Act
      final book = await bookService.createBook('  Trimmed Name  ');

      // Assert
      expect(book.name, 'Trimmed Name');
    });

    test('should handle book name with special characters', () async {
      // Act
      final book = await bookService.createBook('医生-张三 (Dr. Zhang)');

      // Assert
      expect(book.name, '医生-张三 (Dr. Zhang)');
    });

    test('should allow updating book to same name', () async {
      // Arrange
      final book = await bookService.createBook('Same Name');

      // Act - Should not throw exception
      final updatedBook = await bookService.updateBookName(book.id!, 'Same Name');

      // Assert
      expect(updatedBook.name, 'Same Name');
    });

    test('should delete book with appointments', () async {
      // Arrange
      final book = await bookService.createBook('Book with Appointments');
      final appointment = Appointment(
        bookId: book.id!,
        startTime: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await databaseService.createAppointment(appointment);

      // Act - Should not throw exception (cascade delete)
      await bookService.deleteBook(book.id!);

      // Assert
      final retrievedBook = await bookService.getBookById(book.id!);
      expect(retrievedBook, isNull);

      final appointmentCount = await databaseService.getAppointmentCountByBook(book.id!);
      expect(appointmentCount, 0);
    });
  });
}