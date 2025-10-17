import 'package:flutter/foundation.dart';
import '../models/appointment.dart';
import '../services/appointment_service.dart';

/// Appointment状态管理Provider
class AppointmentProvider extends ChangeNotifier {
  final AppointmentService _appointmentService = AppointmentService();

  List<Appointment> _appointments = [];
  Appointment? _currentAppointment;
  DateTime _selectedDate = DateTime.now();
  int? _currentBookId;
  bool _isLoading = false;
  String? _errorMessage;

  // Getters
  List<Appointment> get appointments => _appointments;
  Appointment? get currentAppointment => _currentAppointment;
  DateTime get selectedDate => _selectedDate;
  int? get currentBookId => _currentBookId;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// 设置当前book ID
  void setCurrentBookId(int bookId) {
    if (_currentBookId != bookId) {
      _currentBookId = bookId;
      _clearCurrentAppointment();
      // 自动加载该book的appointments
      loadAppointmentsByDate(_selectedDate);
    }
  }

  /// 设置选中的日期
  void setSelectedDate(DateTime date) {
    _selectedDate = DateTime(date.year, date.month, date.day);
    if (_currentBookId != null) {
      loadAppointmentsByDate(_selectedDate);
    }
    notifyListeners();
  }

  /// 加载指定日期的appointments
  Future<void> loadAppointmentsByDate(DateTime date) async {
    if (_currentBookId == null) return;

    _setLoading(true);
    _clearError();

    try {
      _appointments = await _appointmentService.getAppointmentsByDate(_currentBookId!, date);
      notifyListeners();
    } catch (e) {
      _setError('加载预约失败: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// 加载今天的appointments
  Future<void> loadTodayAppointments() async {
    if (_currentBookId == null) return;

    _setLoading(true);
    _clearError();

    try {
      _appointments = await _appointmentService.getTodayAppointments(_currentBookId!);
      _selectedDate = DateTime.now();
      notifyListeners();
    } catch (e) {
      _setError('加载今日预约失败: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// 创建新appointment
  Future<bool> createAppointment({
    required DateTime startTime,
    int duration = 0,
    String? name,
    String? recordNumber,
    String? type,
  }) async {
    if (_currentBookId == null) {
      _setError('请先选择预约册');
      return false;
    }

    _clearError();

    try {
      final newAppointment = await _appointmentService.createAppointment(
        bookId: _currentBookId!,
        startTime: startTime,
        duration: duration,
        name: name,
        recordNumber: recordNumber,
        type: type,
      );

      // 如果新建的appointment在当前选中的日期，添加到列表中
      if (_isSameDay(startTime, _selectedDate)) {
        _appointments.add(newAppointment);
        _sortAppointments();
      }

      notifyListeners();
      return true;
    } catch (e) {
      _setError('创建预约失败: $e');
      return false;
    }
  }

  /// 更新appointment
  Future<bool> updateAppointment(Appointment appointment) async {
    _clearError();

    try {
      final updatedAppointment = await _appointmentService.updateAppointment(appointment);

      // 更新本地列表
      final index = _appointments.indexWhere((a) => a.id == appointment.id);
      if (index != -1) {
        _appointments[index] = updatedAppointment;
      }

      // 如果当前选中的appointment被更新了，也要更新
      if (_currentAppointment?.id == appointment.id) {
        _currentAppointment = updatedAppointment;
      }

      notifyListeners();
      return true;
    } catch (e) {
      _setError('更新预约失败: $e');
      return false;
    }
  }

  /// 更新appointment的笔记
  Future<bool> updateAppointmentNotes(int appointmentId, List<Stroke> noteStrokes) async {
    _clearError();

    try {
      final updatedAppointment = await _appointmentService.updateAppointmentNotes(
        appointmentId,
        noteStrokes,
      );

      // 更新本地列表
      final index = _appointments.indexWhere((a) => a.id == appointmentId);
      if (index != -1) {
        _appointments[index] = updatedAppointment;
      }

      // 如果当前选中的appointment被更新了，也要更新
      if (_currentAppointment?.id == appointmentId) {
        _currentAppointment = updatedAppointment;
      }

      notifyListeners();
      return true;
    } catch (e) {
      _setError('保存笔记失败: $e');
      return false;
    }
  }

  /// 删除appointment
  Future<bool> deleteAppointment(int id) async {
    _clearError();

    try {
      await _appointmentService.deleteAppointment(id);

      // 从本地列表中移除
      _appointments.removeWhere((a) => a.id == id);

      // 如果删除的是当前选中的appointment，清空选择
      if (_currentAppointment?.id == id) {
        _currentAppointment = null;
      }

      notifyListeners();
      return true;
    } catch (e) {
      _setError('删除预约失败: $e');
      return false;
    }
  }

  /// 设置当前选中的appointment
  void setCurrentAppointment(Appointment appointment) {
    _currentAppointment = appointment;
    notifyListeners();
  }

  /// 根据ID加载appointment详情
  Future<void> loadAppointmentById(int id) async {
    _clearError();

    try {
      final appointment = await _appointmentService.getAppointmentById(id);
      if (appointment != null) {
        _currentAppointment = appointment;
        notifyListeners();
      }
    } catch (e) {
      _setError('加载预约详情失败: $e');
    }
  }

  /// 清空当前选中的appointment
  void _clearCurrentAppointment() {
    _currentAppointment = null;
    notifyListeners();
  }

  /// 验证appointment数据
  Future<ValidationResult> validateAppointment({
    required DateTime startTime,
    int duration = 0,
    String? name,
    String? recordNumber,
    String? type,
    int? excludeId,
  }) async {
    if (_currentBookId == null) {
      return const ValidationResult(
        isValid: false,
        errorMessage: '请先选择预约册',
      );
    }

    try {
      return await _appointmentService.validateAppointment(
        bookId: _currentBookId!,
        startTime: startTime,
        duration: duration,
        name: name,
        recordNumber: recordNumber,
        type: type,
        excludeId: excludeId,
      );
    } catch (e) {
      return ValidationResult(
        isValid: false,
        errorMessage: '验证失败: $e',
      );
    }
  }

  /// 获取指定时间范围的appointments
  Future<List<Appointment>> getAppointmentsByTimeRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    if (_currentBookId == null) return [];

    try {
      return await _appointmentService.getAppointmentsByTimeRange(
        _currentBookId!,
        startDate,
        endDate,
      );
    } catch (e) {
      _setError('获取预约列表失败: $e');
      return [];
    }
  }

  /// 按开始时间排序appointments
  void _sortAppointments() {
    _appointments.sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  /// 检查两个日期是否是同一天
  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
           date1.month == date2.month &&
           date1.day == date2.day;
  }

  /// 设置加载状态
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  /// 设置错误信息
  void _setError(String error) {
    _errorMessage = error;
    notifyListeners();
  }

  /// 清空错误信息
  void _clearError() {
    _errorMessage = null;
  }

  /// 刷新当前日期的appointments
  Future<void> refresh() async {
    if (_currentBookId != null) {
      await loadAppointmentsByDate(_selectedDate);
    }
  }

  /// 清空所有数据
  void clear() {
    _appointments.clear();
    _currentAppointment = null;
    _currentBookId = null;
    _selectedDate = DateTime.now();
    _clearError();
    notifyListeners();
  }
}