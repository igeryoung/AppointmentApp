import '../models/appointment.dart';
import '../models/book.dart';
import 'database_service.dart';

/// Appointment业务服务 - 处理预约相关的业务逻辑
class AppointmentService {
  final DatabaseService _databaseService = DatabaseService();

  /// 获取指定book在指定日期的appointments
  Future<List<Appointment>> getAppointmentsByDate(int bookId, DateTime date) async {
    try {
      // 验证book存在
      final book = await _databaseService.getBookById(bookId);
      if (book == null) {
        throw AppointmentServiceException('预约册不存在');
      }

      return await _databaseService.getAppointmentsByBookAndDate(bookId, date);
    } catch (e) {
      if (e is AppointmentServiceException) rethrow;
      throw AppointmentServiceException('获取预约列表失败: $e');
    }
  }

  /// 获取今天的appointments
  Future<List<Appointment>> getTodayAppointments(int bookId) async {
    return await getAppointmentsByDate(bookId, DateTime.now());
  }

  /// 根据ID获取appointment
  Future<Appointment?> getAppointmentById(int id) async {
    try {
      return await _databaseService.getAppointmentById(id);
    } catch (e) {
      throw AppointmentServiceException('获取预约详情失败: $e');
    }
  }

  /// 创建新appointment
  Future<Appointment> createAppointment({
    required int bookId,
    required DateTime startTime,
    int duration = 0,
    String? name,
    String? recordNumber,
    String? type,
  }) async {
    // 业务验证
    await _validateAppointmentData(
      bookId: bookId,
      startTime: startTime,
      duration: duration,
      name: name,
      recordNumber: recordNumber,
      type: type,
    );

    // 检查时间冲突
    await _checkTimeConflict(bookId, startTime, duration);

    try {
      final now = DateTime.now();
      final appointment = Appointment(
        bookId: bookId,
        startTime: startTime,
        duration: duration,
        name: name?.trim(),
        recordNumber: recordNumber?.trim(),
        type: type?.trim(),
        noteStrokes: const [],
        createdAt: now,
        updatedAt: now,
      );

      return await _databaseService.createAppointment(appointment);
    } catch (e) {
      throw AppointmentServiceException('创建预约失败: $e');
    }
  }

  /// 更新appointment
  Future<Appointment> updateAppointment(Appointment appointment) async {
    if (appointment.id == null) {
      throw AppointmentServiceException('无效的预约ID');
    }

    // 检查appointment是否存在
    final existing = await _databaseService.getAppointmentById(appointment.id!);
    if (existing == null) {
      throw AppointmentServiceException('预约不存在');
    }

    // 业务验证
    await _validateAppointmentData(
      bookId: appointment.bookId,
      startTime: appointment.startTime,
      duration: appointment.duration,
      name: appointment.name,
      recordNumber: appointment.recordNumber,
      type: appointment.type,
    );

    // 检查时间冲突（排除当前appointment）
    await _checkTimeConflict(
      appointment.bookId,
      appointment.startTime,
      appointment.duration,
      excludeId: appointment.id,
    );

    try {
      return await _databaseService.updateAppointment(appointment);
    } catch (e) {
      throw AppointmentServiceException('更新预约失败: $e');
    }
  }

  /// 更新appointment的笔记
  Future<Appointment> updateAppointmentNotes(int appointmentId, List<Stroke> noteStrokes) async {
    final existing = await _databaseService.getAppointmentById(appointmentId);
    if (existing == null) {
      throw AppointmentServiceException('预约不存在');
    }

    try {
      final updatedAppointment = existing.copyWith(noteStrokes: noteStrokes);
      return await _databaseService.updateAppointment(updatedAppointment);
    } catch (e) {
      throw AppointmentServiceException('保存笔记失败: $e');
    }
  }

  /// 删除appointment
  Future<void> deleteAppointment(int id) async {
    // 检查appointment是否存在
    final existing = await _databaseService.getAppointmentById(id);
    if (existing == null) {
      throw AppointmentServiceException('预约不存在');
    }

    try {
      await _databaseService.deleteAppointment(id);
    } catch (e) {
      throw AppointmentServiceException('删除预约失败: $e');
    }
  }

  /// 获取appointment的详细信息（包含book信息）
  Future<AppointmentDetails?> getAppointmentDetails(int id) async {
    try {
      final appointment = await _databaseService.getAppointmentById(id);
      if (appointment == null) return null;

      final book = await _databaseService.getBookById(appointment.bookId);
      if (book == null) {
        throw AppointmentServiceException('关联的预约册不存在');
      }

      return AppointmentDetails(
        appointment: appointment,
        book: book,
      );
    } catch (e) {
      if (e is AppointmentServiceException) rethrow;
      throw AppointmentServiceException('获取预约详情失败: $e');
    }
  }

  /// 获取指定时间段的appointments
  Future<List<Appointment>> getAppointmentsByTimeRange(
    int bookId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      // 验证book存在
      final book = await _databaseService.getBookById(bookId);
      if (book == null) {
        throw AppointmentServiceException('预约册不存在');
      }

      // 获取时间范围内的appointments
      final appointments = <Appointment>[];
      final currentDate = DateTime(startDate.year, startDate.month, startDate.day);
      final end = DateTime(endDate.year, endDate.month, endDate.day);

      var date = currentDate;
      while (date.isBefore(end) || date.isAtSameMomentAs(end)) {
        final dayAppointments = await _databaseService.getAppointmentsByBookAndDate(bookId, date);
        appointments.addAll(dayAppointments);
        date = date.add(const Duration(days: 1));
      }

      // 按开始时间排序
      appointments.sort((a, b) => a.startTime.compareTo(b.startTime));
      return appointments;
    } catch (e) {
      if (e is AppointmentServiceException) rethrow;
      throw AppointmentServiceException('获取预约列表失败: $e');
    }
  }

  /// 验证预约数据
  Future<void> _validateAppointmentData({
    required int bookId,
    required DateTime startTime,
    required int duration,
    String? name,
    String? recordNumber,
    String? type,
  }) async {
    // 验证book存在
    final book = await _databaseService.getBookById(bookId);
    if (book == null) {
      throw AppointmentServiceException('预约册不存在');
    }

    // 验证时间
    if (startTime.isBefore(DateTime.now().subtract(const Duration(days: 365)))) {
      throw AppointmentServiceException('预约时间不能超过一年前');
    }

    if (startTime.isAfter(DateTime.now().add(const Duration(days: 365 * 2)))) {
      throw AppointmentServiceException('预约时间不能超过两年后');
    }

    // 验证duration
    if (duration < 0) {
      throw AppointmentServiceException('预约时长不能为负数');
    }

    if (duration > 24 * 60) {
      throw AppointmentServiceException('预约时长不能超过24小时');
    }

    // 验证字段长度
    if (name != null && name.trim().length > 100) {
      throw AppointmentServiceException('预约名称不能超过100个字符');
    }

    if (recordNumber != null && recordNumber.trim().length > 50) {
      throw AppointmentServiceException('记录编号不能超过50个字符');
    }

    if (type != null && type.trim().length > 50) {
      throw AppointmentServiceException('预约类型不能超过50个字符');
    }
  }

  /// 检查时间冲突
  Future<void> _checkTimeConflict(
    int bookId,
    DateTime startTime,
    int duration, {
    int? excludeId,
  }) async {
    final dayAppointments = await _databaseService.getAppointmentsByBookAndDate(
      bookId,
      startTime,
    );

    final endTime = duration > 0 ? startTime.add(Duration(minutes: duration)) : null;

    for (final appointment in dayAppointments) {
      // 跳过当前appointment
      if (excludeId != null && appointment.id == excludeId) continue;

      // 如果任一预约是开放式的，只检查开始时间冲突
      if (appointment.duration == 0 || duration == 0) {
        if (appointment.startTime.isAtSameMomentAs(startTime)) {
          throw AppointmentServiceException('该时间段已有预约');
        }
        continue;
      }

      // 检查时间重叠
      final appointmentEndTime = appointment.startTime.add(Duration(minutes: appointment.duration));

      final hasOverlap = startTime.isBefore(appointmentEndTime) &&
                        (endTime?.isAfter(appointment.startTime) ?? false);

      if (hasOverlap) {
        throw AppointmentServiceException('该时间段与现有预约冲突');
      }
    }
  }

  /// 验证appointment数据（不创建，仅验证）
  Future<ValidationResult> validateAppointment({
    required int bookId,
    required DateTime startTime,
    int duration = 0,
    String? name,
    String? recordNumber,
    String? type,
    int? excludeId,
  }) async {
    try {
      await _validateAppointmentData(
        bookId: bookId,
        startTime: startTime,
        duration: duration,
        name: name,
        recordNumber: recordNumber,
        type: type,
      );

      await _checkTimeConflict(bookId, startTime, duration, excludeId: excludeId);

      return const ValidationResult(isValid: true);
    } catch (e) {
      return ValidationResult(
        isValid: false,
        errorMessage: e.toString().replaceFirst('AppointmentServiceException: ', ''),
      );
    }
  }
}

/// Appointment业务异常
class AppointmentServiceException implements Exception {
  final String message;
  AppointmentServiceException(this.message);

  @override
  String toString() => 'AppointmentServiceException: $message';
}

/// Appointment详情（包含关联的book信息）
class AppointmentDetails {
  final Appointment appointment;
  final Book book;

  const AppointmentDetails({
    required this.appointment,
    required this.book,
  });

  @override
  String toString() {
    return 'AppointmentDetails(appointment: ${appointment.name}, book: ${book.name})';
  }
}

/// 验证结果
class ValidationResult {
  final bool isValid;
  final String? errorMessage;

  const ValidationResult({
    required this.isValid,
    this.errorMessage,
  });

  @override
  String toString() {
    return 'ValidationResult(isValid: $isValid, errorMessage: $errorMessage)';
  }
}