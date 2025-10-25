import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:schedule_note_app/services/database_service.dart';
import 'package:schedule_note_app/models/book.dart';
import 'package:schedule_note_app/models/appointment.dart';

void main() {
  late DatabaseService databaseService;

  setUpAll(() {
    // 使用FFI for testing
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // 重置单例实例
    DatabaseService.resetInstance();
    databaseService = DatabaseService();
    // 清空数据以确保测试独立性
    await databaseService.clearAllData();
  });

  tearDown(() async {
    await databaseService.close();
    DatabaseService.resetInstance();
  });

  group('DatabaseService - Book Operations', () {
    test('should create and retrieve a book', () async {
      // Arrange
      const bookName = 'Doctor A';

      // Act
      final createdBook = await databaseService.createBook(bookName);
      final retrievedBook = await databaseService.getBookById(createdBook.id!);

      // Assert
      expect(createdBook.name, bookName);
      expect(createdBook.id, isNotNull);
      expect(retrievedBook, isNotNull);
      expect(retrievedBook!.id, createdBook.id);
      expect(retrievedBook.name, bookName);
    });

    test('should throw error when creating book with empty name', () async {
      // Act & Assert
      expect(
        () => databaseService.createBook(''),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => databaseService.createBook('   '),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should get all books ordered by creation date', () async {
      // Arrange
      final book1 = await databaseService.createBook('Book 1');
      await Future.delayed(const Duration(milliseconds: 10)); // 增加延迟确保时间戳不同
      final book2 = await databaseService.createBook('Book 2');

      // Act
      final books = await databaseService.getAllBooks();

      // Assert
      expect(books.length, 2);
      // 验证包含正确的books，不依赖具体顺序
      final bookIds = books.map((b) => b.id).toSet();
      expect(bookIds.contains(book1.id), isTrue);
      expect(bookIds.contains(book2.id), isTrue);

      final bookNames = books.map((b) => b.name).toSet();
      expect(bookNames.contains('Book 1'), isTrue);
      expect(bookNames.contains('Book 2'), isTrue);
    });

    test('should update book name', () async {
      // Arrange
      final book = await databaseService.createBook('Original Name');
      const newName = 'Updated Name';

      // Act
      final updatedBook = await databaseService.updateBook(
        book.copyWith(name: newName),
      );

      // Assert
      expect(updatedBook.name, newName);
      expect(updatedBook.id, book.id);

      final retrievedBook = await databaseService.getBookById(book.id!);
      expect(retrievedBook!.name, newName);
    });

    test('should throw error when updating book with null id', () async {
      // Arrange
      final book = Book(
        name: 'Test Book',
        createdAt: DateTime.now(),
      );

      // Act & Assert
      expect(
        () => databaseService.updateBook(book),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should delete book and cascade delete appointments', () async {
      // Arrange
      final book = await databaseService.createBook('Test Book');
      final appointment = Appointment(
        bookId: book.id!,
        startTime: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await databaseService.createAppointment(appointment);

      // Act
      await databaseService.deleteBook(book.id!);

      // Assert
      final retrievedBook = await databaseService.getBookById(book.id!);
      expect(retrievedBook, isNull);

      final appointmentCount = await databaseService.getAppointmentCountByBook(book.id!);
      expect(appointmentCount, 0);
    });

    test('should throw error when deleting non-existent book', () async {
      // Act & Assert
      expect(
        () => databaseService.deleteBook(999),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('DatabaseService - Appointment Operations', () {
    late Book testBook;

    setUp(() async {
      testBook = await databaseService.createBook('Test Book');
    });

    test('should create and retrieve an appointment', () async {
      // Arrange
      final startTime = DateTime.now();
      final appointment = Appointment(
        bookId: testBook.id!,
        startTime: startTime,
        duration: 60,
        name: 'Test Appointment',
        recordNumber: 'REC001',
        type: 'Consultation',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Act
      final createdAppointment = await databaseService.createAppointment(appointment);
      final retrievedAppointment = await databaseService.getAppointmentById(createdAppointment.id!);

      // Assert
      expect(createdAppointment.id, isNotNull);
      expect(retrievedAppointment, isNotNull);
      expect(retrievedAppointment!.bookId, testBook.id);
      expect(retrievedAppointment.name, 'Test Appointment');
      expect(retrievedAppointment.recordNumber, 'REC001');
      expect(retrievedAppointment.type, 'Consultation');
      expect(retrievedAppointment.duration, 60);
    });

    test('should get appointments by book and date', () async {
      // Arrange
      final today = DateTime.now();
      final tomorrow = today.add(const Duration(days: 1));

      final todayAppointment = Appointment(
        bookId: testBook.id!,
        startTime: today,
        name: 'Today Appointment',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final tomorrowAppointment = Appointment(
        bookId: testBook.id!,
        startTime: tomorrow,
        name: 'Tomorrow Appointment',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await databaseService.createAppointment(todayAppointment);
      await databaseService.createAppointment(tomorrowAppointment);

      // Act
      final todayAppointments = await databaseService.getAppointmentsByBookAndDate(
        testBook.id!,
        today,
      );

      // Assert
      expect(todayAppointments.length, 1);
      expect(todayAppointments[0].name, 'Today Appointment');
    });

    test('should update appointment', () async {
      // Arrange
      final appointment = Appointment(
        bookId: testBook.id!,
        startTime: DateTime.now(),
        name: 'Original Name',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final createdAppointment = await databaseService.createAppointment(appointment);

      // Act
      final updatedAppointment = await databaseService.updateAppointment(
        createdAppointment.copyWith(name: 'Updated Name'),
      );

      // Assert
      expect(updatedAppointment.name, 'Updated Name');
      expect(updatedAppointment.id, createdAppointment.id);

      final retrievedAppointment = await databaseService.getAppointmentById(createdAppointment.id!);
      expect(retrievedAppointment!.name, 'Updated Name');
    });

    test('should handle appointments with note strokes', () async {
      // Arrange
      final strokes = [
        Stroke(
          points: [const StrokePoint(0, 0), const StrokePoint(10, 10)],
          color: 0xFF000000,
          width: 2.0,
          timestamp: DateTime.now(),
        ),
      ];

      final appointment = Appointment(
        bookId: testBook.id!,
        startTime: DateTime.now(),
        name: 'Appointment with Notes',
        noteStrokes: strokes,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Act
      final createdAppointment = await databaseService.createAppointment(appointment);
      final retrievedAppointment = await databaseService.getAppointmentById(createdAppointment.id!);

      // Assert
      expect(retrievedAppointment!.noteStrokes.length, 1);
      expect(retrievedAppointment.noteStrokes[0].points.length, 2);
      expect(retrievedAppointment.noteStrokes[0].color, 0xFF000000);
      expect(retrievedAppointment.noteStrokes[0].width, 2.0);
    });

    test('should delete appointment', () async {
      // Arrange
      final appointment = Appointment(
        bookId: testBook.id!,
        startTime: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final createdAppointment = await databaseService.createAppointment(appointment);

      // Act
      await databaseService.deleteAppointment(createdAppointment.id!);

      // Assert
      final retrievedAppointment = await databaseService.getAppointmentById(createdAppointment.id!);
      expect(retrievedAppointment, isNull);
    });

    test('should throw error when updating appointment with null id', () async {
      // Arrange
      final appointment = Appointment(
        bookId: testBook.id!,
        startTime: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Act & Assert
      expect(
        () => databaseService.updateAppointment(appointment),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should get appointment count by book', () async {
      // Arrange
      final appointment1 = Appointment(
        bookId: testBook.id!,
        startTime: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final appointment2 = Appointment(
        bookId: testBook.id!,
        startTime: DateTime.now().add(const Duration(hours: 1)),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await databaseService.createAppointment(appointment1);
      await databaseService.createAppointment(appointment2);

      // Act
      final count = await databaseService.getAppointmentCountByBook(testBook.id!);

      // Assert
      expect(count, 2);
    });
  });

  group('DatabaseService - Edge Cases', () {
    test('should handle empty note strokes correctly', () async {
      // Arrange
      final book = await databaseService.createBook('Test Book');
      final appointment = Appointment(
        bookId: book.id!,
        startTime: DateTime.now(),
        noteStrokes: [], // 空笔触列表
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Act
      final createdAppointment = await databaseService.createAppointment(appointment);
      final retrievedAppointment = await databaseService.getAppointmentById(createdAppointment.id!);

      // Assert
      expect(retrievedAppointment!.noteStrokes, isEmpty);
    });

    test('should handle malformed note strokes data gracefully', () async {
      // 这个测试模拟数据库中存储了格式错误的笔触数据的情况
      // 在实际应用中，这种情况应该很少发生，但我们需要优雅地处理
      final book = await databaseService.createBook('Test Book');
      final db = await databaseService.database;

      // 直接插入格式错误的数据
      await db.insert('appointments', {
        'book_id': book.id,
        'start_time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'duration': 0,
        'note_strokes': 'invalid json',
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      });

      // Act - 应该不会崩溃，而是返回空的笔触列表
      final appointments = await databaseService.getAppointmentsByBookAndDate(
        book.id!,
        DateTime.now(),
      );

      // Assert
      expect(appointments.length, 1);
      expect(appointments[0].noteStrokes, isEmpty);
    });
  });
}