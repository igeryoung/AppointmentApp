import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:schedule_note_app/services/appointment_service.dart';
import 'package:schedule_note_app/services/database_service.dart';
import 'package:schedule_note_app/models/book.dart';
import 'package:schedule_note_app/models/appointment.dart';

void main() {
  late AppointmentService appointmentService;
  late DatabaseService databaseService;
  late Book testBook;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    DatabaseService.resetInstance();
    databaseService = DatabaseService();
    appointmentService = AppointmentService();
    await databaseService.clearAllData();

    // Create a test book for appointments
    testBook = await databaseService.createBook('Test Book');
  });

  tearDown(() async {
    await databaseService.close();
    DatabaseService.resetInstance();
  });

  group('AppointmentService - Basic Operations', () {
    test('should create appointment with valid data', () async {
      // Arrange
      final startTime = DateTime.now();

      // Act
      final appointment = await appointmentService.createAppointment(
        bookId: testBook.id!,
        startTime: startTime,
        duration: 60,
        name: 'Test Appointment',
        recordNumber: 'REC001',
        type: 'Consultation',
      );

      // Assert
      expect(appointment.id, isNotNull);
      expect(appointment.bookId, testBook.id);
      expect(appointment.startTime, startTime);
      expect(appointment.duration, 60);
      expect(appointment.name, 'Test Appointment');
      expect(appointment.recordNumber, 'REC001');
      expect(appointment.type, 'Consultation');
    });

    test('should get appointments by date', () async {
      // Arrange
      final today = DateTime.now();
      final tomorrow = today.add(const Duration(days: 1));

      await appointmentService.createAppointment(
        bookId: testBook.id!,
        startTime: today,
        name: 'Today Appointment',
      );

      await appointmentService.createAppointment(
        bookId: testBook.id!,
        startTime: tomorrow,
        name: 'Tomorrow Appointment',
      );

      // Act
      final todayAppointments = await appointmentService.getAppointmentsByDate(
        testBook.id!,
        today,
      );

      // Assert
      expect(todayAppointments.length, 1);
      expect(todayAppointments[0].name, 'Today Appointment');
    });

    test('should get today appointments', () async {
      // Arrange
      final today = DateTime.now();
      await appointmentService.createAppointment(
        bookId: testBook.id!,
        startTime: today,
        name: 'Today Appointment',
      );

      // Act
      final appointments = await appointmentService.getTodayAppointments(testBook.id!);

      // Assert
      expect(appointments.length, 1);
      expect(appointments[0].name, 'Today Appointment');
    });

    test('should get appointment by id', () async {
      // Arrange
      final created = await appointmentService.createAppointment(
        bookId: testBook.id!,
        startTime: DateTime.now(),
        name: 'Test Appointment',
      );

      // Act
      final retrieved = await appointmentService.getAppointmentById(created.id!);

      // Assert
      expect(retrieved, isNotNull);
      expect(retrieved!.id, created.id);
      expect(retrieved.name, 'Test Appointment');
    });

    test('should update appointment', () async {
      // Arrange
      final appointment = await appointmentService.createAppointment(
        bookId: testBook.id!,
        startTime: DateTime.now(),
        name: 'Original Name',
      );

      // Act
      final updated = await appointmentService.updateAppointment(
        appointment.copyWith(name: 'Updated Name'),
      );

      // Assert
      expect(updated.name, 'Updated Name');
      expect(updated.id, appointment.id);
    });

    test('should delete appointment', () async {
      // Arrange
      final appointment = await appointmentService.createAppointment(
        bookId: testBook.id!,
        startTime: DateTime.now(),
        name: 'To Delete',
      );

      // Act
      await appointmentService.deleteAppointment(appointment.id!);

      // Assert
      final retrieved = await appointmentService.getAppointmentById(appointment.id!);
      expect(retrieved, isNull);
    });

    test('should update appointment notes', () async {
      // Arrange
      final appointment = await appointmentService.createAppointment(
        bookId: testBook.id!,
        startTime: DateTime.now(),
        name: 'Test Appointment',
      );

      final strokes = [
        Stroke(
          points: [const StrokePoint(0, 0), const StrokePoint(10, 10)],
          color: 0xFF000000,
          width: 2.0,
          timestamp: DateTime.now(),
        ),
      ];

      // Act
      final updated = await appointmentService.updateAppointmentNotes(
        appointment.id!,
        strokes,
      );

      // Assert
      expect(updated.noteStrokes.length, 1);
      expect(updated.noteStrokes[0].points.length, 2);
    });
  });

  group('AppointmentService - Validation Tests', () {
    test('should throw exception for non-existent book', () async {
      // Act & Assert
      expect(
        () => appointmentService.createAppointment(
          bookId: 999,
          startTime: DateTime.now(),
        ),
        throwsA(isA<AppointmentServiceException>()),
      );
    });

    test('should throw exception for appointment too far in past', () async {
      // Arrange
      final tooOld = DateTime.now().subtract(const Duration(days: 366));

      // Act & Assert
      expect(
        () => appointmentService.createAppointment(
          bookId: testBook.id!,
          startTime: tooOld,
        ),
        throwsA(isA<AppointmentServiceException>()),
      );
    });

    test('should throw exception for appointment too far in future', () async {
      // Arrange
      final tooFar = DateTime.now().add(const Duration(days: 366 * 2 + 1));

      // Act & Assert
      expect(
        () => appointmentService.createAppointment(
          bookId: testBook.id!,
          startTime: tooFar,
        ),
        throwsA(isA<AppointmentServiceException>()),
      );
    });

    test('should throw exception for negative duration', () async {
      // Act & Assert
      expect(
        () => appointmentService.createAppointment(
          bookId: testBook.id!,
          startTime: DateTime.now(),
          duration: -30,
        ),
        throwsA(isA<AppointmentServiceException>()),
      );
    });

    test('should throw exception for duration too long', () async {
      // Act & Assert
      expect(
        () => appointmentService.createAppointment(
          bookId: testBook.id!,
          startTime: DateTime.now(),
          duration: 25 * 60, // 25 hours
        ),
        throwsA(isA<AppointmentServiceException>()),
      );
    });

    test('should throw exception for name too long', () async {
      // Arrange
      final longName = 'A' * 101; // 101 characters

      // Act & Assert
      expect(
        () => appointmentService.createAppointment(
          bookId: testBook.id!,
          startTime: DateTime.now(),
          name: longName,
        ),
        throwsA(isA<AppointmentServiceException>()),
      );
    });

    test('should throw exception for record number too long', () async {
      // Arrange
      final longRecordNumber = 'A' * 51; // 51 characters

      // Act & Assert
      expect(
        () => appointmentService.createAppointment(
          bookId: testBook.id!,
          startTime: DateTime.now(),
          recordNumber: longRecordNumber,
        ),
        throwsA(isA<AppointmentServiceException>()),
      );
    });

    test('should throw exception for type too long', () async {
      // Arrange
      final longType = 'A' * 51; // 51 characters

      // Act & Assert
      expect(
        () => appointmentService.createAppointment(
          bookId: testBook.id!,
          startTime: DateTime.now(),
          type: longType,
        ),
        throwsA(isA<AppointmentServiceException>()),
      );
    });

    test('should throw exception when updating non-existent appointment', () async {
      // Arrange
      final appointment = Appointment(
        id: 999,
        bookId: testBook.id!,
        startTime: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Act & Assert
      expect(
        () => appointmentService.updateAppointment(appointment),
        throwsA(isA<AppointmentServiceException>()),
      );
    });

    test('should throw exception when deleting non-existent appointment', () async {
      // Act & Assert
      expect(
        () => appointmentService.deleteAppointment(999),
        throwsA(isA<AppointmentServiceException>()),
      );
    });
  });

  group('AppointmentService - Time Conflict Tests', () {
    test('should detect time conflict for fixed duration appointments', () async {
      // Arrange
      final startTime = DateTime.now();
      await appointmentService.createAppointment(
        bookId: testBook.id!,
        startTime: startTime,
        duration: 60,
        name: 'First Appointment',
      );

      // Act & Assert - Overlapping appointment
      expect(
        () => appointmentService.createAppointment(
          bookId: testBook.id!,
          startTime: startTime.add(const Duration(minutes: 30)),
          duration: 60,
          name: 'Conflicting Appointment',
        ),
        throwsA(isA<AppointmentServiceException>()),
      );
    });

    test('should detect exact time conflict for open-ended appointments', () async {
      // Arrange - 使用当前时间的固定部分，确保完全相同
      final now = DateTime.now();
      final startTime = DateTime(now.year, now.month, now.day, 10, 0, 0);
      await appointmentService.createAppointment(
        bookId: testBook.id!,
        startTime: startTime,
        duration: 0, // Open-ended
        name: 'First Appointment',
      );

      // Act & Assert - Same start time
      expect(
        () => appointmentService.createAppointment(
          bookId: testBook.id!,
          startTime: startTime, // 完全相同的时间
          duration: 0,
          name: 'Conflicting Appointment',
        ),
        throwsA(isA<AppointmentServiceException>()),
      );
    });

    test('should allow non-overlapping appointments', () async {
      // Arrange
      final startTime = DateTime.now();
      await appointmentService.createAppointment(
        bookId: testBook.id!,
        startTime: startTime,
        duration: 60,
        name: 'First Appointment',
      );

      // Act - Non-overlapping appointment should succeed
      final appointment = await appointmentService.createAppointment(
        bookId: testBook.id!,
        startTime: startTime.add(const Duration(minutes: 60)),
        duration: 60,
        name: 'Second Appointment',
      );

      // Assert
      expect(appointment.name, 'Second Appointment');
    });

    test('should allow updating appointment to same time', () async {
      // Arrange
      final appointment = await appointmentService.createAppointment(
        bookId: testBook.id!,
        startTime: DateTime.now(),
        duration: 60,
        name: 'Test Appointment',
      );

      // Act - Should not throw exception
      final updated = await appointmentService.updateAppointment(
        appointment.copyWith(name: 'Updated Name'),
      );

      // Assert
      expect(updated.name, 'Updated Name');
    });
  });

  group('AppointmentService - Advanced Features', () {
    test('should get appointment details with book info', () async {
      // Arrange
      final appointment = await appointmentService.createAppointment(
        bookId: testBook.id!,
        startTime: DateTime.now(),
        name: 'Test Appointment',
      );

      // Act
      final details = await appointmentService.getAppointmentDetails(appointment.id!);

      // Assert
      expect(details, isNotNull);
      expect(details!.appointment.id, appointment.id);
      expect(details.book.id, testBook.id);
      expect(details.book.name, testBook.name);
    });

    test('should return null for non-existent appointment details', () async {
      // Act
      final details = await appointmentService.getAppointmentDetails(999);

      // Assert
      expect(details, isNull);
    });

    test('should get appointments by time range', () async {
      // Arrange
      final today = DateTime.now();
      final tomorrow = today.add(const Duration(days: 1));
      final dayAfter = today.add(const Duration(days: 2));

      await appointmentService.createAppointment(
        bookId: testBook.id!,
        startTime: today,
        name: 'Today',
      );

      await appointmentService.createAppointment(
        bookId: testBook.id!,
        startTime: tomorrow,
        name: 'Tomorrow',
      );

      await appointmentService.createAppointment(
        bookId: testBook.id!,
        startTime: dayAfter,
        name: 'Day After',
      );

      // Act
      final appointments = await appointmentService.getAppointmentsByTimeRange(
        testBook.id!,
        today,
        tomorrow,
      );

      // Assert
      expect(appointments.length, 2);
      final names = appointments.map((a) => a.name).toList();
      expect(names.contains('Today'), isTrue);
      expect(names.contains('Tomorrow'), isTrue);
      expect(names.contains('Day After'), isFalse);
    });

    test('should validate appointment data correctly', () async {
      // Test valid appointment
      var result = await appointmentService.validateAppointment(
        bookId: testBook.id!,
        startTime: DateTime.now().add(const Duration(hours: 1)),
        duration: 60,
        name: 'Valid Appointment',
      );
      expect(result.isValid, isTrue);

      // Test invalid book
      result = await appointmentService.validateAppointment(
        bookId: 999,
        startTime: DateTime.now(),
      );
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('不存在'));

      // Test time conflict
      final startTime = DateTime.now().add(const Duration(hours: 2));
      await appointmentService.createAppointment(
        bookId: testBook.id!,
        startTime: startTime,
        duration: 60,
      );

      result = await appointmentService.validateAppointment(
        bookId: testBook.id!,
        startTime: startTime.add(const Duration(minutes: 30)),
        duration: 60,
      );
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('冲突'));
    });
  });

  group('AppointmentService - Edge Cases', () {
    test('should trim whitespace from string fields', () async {
      // Act
      final appointment = await appointmentService.createAppointment(
        bookId: testBook.id!,
        startTime: DateTime.now(),
        name: '  Trimmed Name  ',
        recordNumber: '  REC001  ',
        type: '  Consultation  ',
      );

      // Assert
      expect(appointment.name, 'Trimmed Name');
      expect(appointment.recordNumber, 'REC001');
      expect(appointment.type, 'Consultation');
    });

    test('should handle appointment with only required fields', () async {
      // Act
      final appointment = await appointmentService.createAppointment(
        bookId: testBook.id!,
        startTime: DateTime.now(),
      );

      // Assert
      expect(appointment.bookId, testBook.id);
      expect(appointment.name, isNull);
      expect(appointment.recordNumber, isNull);
      expect(appointment.type, isNull);
      expect(appointment.duration, 0);
    });

    test('should handle appointment with special characters', () async {
      // Act
      final appointment = await appointmentService.createAppointment(
        bookId: testBook.id!,
        startTime: DateTime.now(),
        name: '张三-复诊 (Follow-up)',
        recordNumber: 'REC-2024-001',
        type: '专科门诊',
      );

      // Assert
      expect(appointment.name, '张三-复诊 (Follow-up)');
      expect(appointment.recordNumber, 'REC-2024-001');
      expect(appointment.type, '专科门诊');
    });

    test('should update notes for non-existent appointment should throw', () async {
      // Act & Assert
      expect(
        () => appointmentService.updateAppointmentNotes(999, []),
        throwsA(isA<AppointmentServiceException>()),
      );
    });
  });
}