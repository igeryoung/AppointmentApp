import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/book_provider.dart';
import '../providers/appointment_provider.dart';
import '../models/appointment.dart';

/// 日历屏幕 - 显示选中book的日历视图
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  @override
  void initState() {
    super.initState();
    // 页面加载时加载今天的appointments
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppointmentProvider>().loadTodayAppointments();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Consumer<BookProvider>(
          builder: (context, bookProvider, child) {
            final currentBook = bookProvider.currentBook;
            return Text(currentBook?.name ?? '日历');
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.today),
            onPressed: () {
              context.read<AppointmentProvider>().setSelectedDate(DateTime.now());
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<AppointmentProvider>().refresh(),
          ),
        ],
      ),
      body: Column(
        children: [
          _DateSelector(),
          Expanded(child: _AppointmentList()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateAppointmentDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  /// 显示创建预约对话框
  void _showCreateAppointmentDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const _CreateAppointmentDialog(),
    );
  }
}

/// 日期选择器组件
class _DateSelector extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<AppointmentProvider>(
      builder: (context, appointmentProvider, child) {
        final selectedDate = appointmentProvider.selectedDate;

        return Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              IconButton(
                onPressed: () {
                  final previousDay = selectedDate.subtract(const Duration(days: 1));
                  appointmentProvider.setSelectedDate(previousDay);
                },
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => _showDatePicker(context, selectedDate),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.calendar_today, size: 20, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        Text(
                          _formatDate(selectedDate),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: () {
                  final nextDay = selectedDate.add(const Duration(days: 1));
                  appointmentProvider.setSelectedDate(nextDay);
                },
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 显示日期选择器
  void _showDatePicker(BuildContext context, DateTime selectedDate) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );

    if (picked != null && context.mounted) {
      context.read<AppointmentProvider>().setSelectedDate(picked);
    }
  }

  /// 格式化日期
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final targetDate = DateTime(date.year, date.month, date.day);

    if (targetDate == today) {
      return '今天 (${DateFormat('M月d日').format(date)})';
    } else if (targetDate == today.add(const Duration(days: 1))) {
      return '明天 (${DateFormat('M月d日').format(date)})';
    } else if (targetDate == today.subtract(const Duration(days: 1))) {
      return '昨天 (${DateFormat('M月d日').format(date)})';
    } else {
      return DateFormat('yyyy年M月d日 EEEE').format(date);
    }
  }
}

/// 预约列表组件
class _AppointmentList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<AppointmentProvider>(
      builder: (context, appointmentProvider, child) {
        if (appointmentProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (appointmentProvider.errorMessage != null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red[300],
                ),
                const SizedBox(height: 16),
                Text(
                  appointmentProvider.errorMessage!,
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => appointmentProvider.refresh(),
                  child: const Text('重试'),
                ),
              ],
            ),
          );
        }

        if (appointmentProvider.appointments.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.event_available,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  '暂无预约',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '点击右下角的"+"按钮创建预约',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          physics: const ClampingScrollPhysics(),
          itemCount: appointmentProvider.appointments.length,
          itemBuilder: (context, index) {
            final appointment = appointmentProvider.appointments[index];
            return _AppointmentCard(appointment: appointment);
          },
        );
      },
    );
  }
}

/// 预约卡片组件
class _AppointmentCard extends StatelessWidget {
  final Appointment appointment;

  const _AppointmentCard({required this.appointment});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _getTypeColor(appointment.type).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _getTypeIcon(appointment.type),
            color: _getTypeColor(appointment.type),
          ),
        ),
        title: Text(
          appointment.name ?? '无标题预约',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              _formatTime(appointment),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[700],
              ),
            ),
            if (appointment.recordNumber != null) ...[
              const SizedBox(height: 2),
              Text(
                '记录号: ${appointment.recordNumber}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
            ],
            if (appointment.type != null) ...[
              const SizedBox(height: 2),
              Text(
                '类型: ${appointment.type}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
            ],
          ],
        ),
        trailing: appointment.noteStrokes.isNotEmpty
            ? Icon(
                Icons.note,
                color: Colors.orange[600],
                size: 20,
              )
            : null,
        onTap: () => _openAppointmentDetail(context, appointment),
      ),
    );
  }

  /// 打开预约详情页面
  void _openAppointmentDetail(BuildContext context, Appointment appointment) {
    context.read<AppointmentProvider>().setCurrentAppointment(appointment);
    Navigator.pushNamed(context, '/appointment');
  }

  /// 格式化时间
  String _formatTime(Appointment appointment) {
    final startTime = DateFormat('HH:mm').format(appointment.startTime);
    if (appointment.isOpenEnded) {
      return '$startTime (开放式)';
    } else {
      final endTime = DateFormat('HH:mm').format(appointment.endTime!);
      return '$startTime - $endTime';
    }
  }

  /// 根据类型获取图标
  IconData _getTypeIcon(String? type) {
    switch (type?.toLowerCase()) {
      case '检查':
      case 'examination':
        return Icons.health_and_safety;
      case '咨询':
      case 'consultation':
        return Icons.chat;
      case '治疗':
      case 'treatment':
        return Icons.medical_services;
      case '复诊':
      case 'follow-up':
        return Icons.repeat;
      default:
        return Icons.event;
    }
  }

  /// 根据类型获取颜色
  Color _getTypeColor(String? type) {
    switch (type?.toLowerCase()) {
      case '检查':
      case 'examination':
        return Colors.blue;
      case '咨询':
      case 'consultation':
        return Colors.green;
      case '治疗':
      case 'treatment':
        return Colors.red;
      case '复诊':
      case 'follow-up':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}

/// 创建预约对话框
class _CreateAppointmentDialog extends StatefulWidget {
  const _CreateAppointmentDialog();

  @override
  State<_CreateAppointmentDialog> createState() => _CreateAppointmentDialogState();
}

class _CreateAppointmentDialogState extends State<_CreateAppointmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _recordNumberController = TextEditingController();
  final _typeController = TextEditingController();

  TimeOfDay? _selectedTime;
  int _duration = 0; // 0表示开放式
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    _recordNumberController.dispose();
    _typeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('创建预约'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '预约名称',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value != null && value.trim().length > 100) {
                    return '预约名称不能超过100个字符';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _recordNumberController,
                decoration: const InputDecoration(
                  labelText: '记录编号',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value != null && value.trim().length > 50) {
                    return '记录编号不能超过50个字符';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _typeController,
                decoration: const InputDecoration(
                  labelText: '预约类型',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value != null && value.trim().length > 50) {
                    return '预约类型不能超过50个字符';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.access_time),
                title: Text(_selectedTime == null ? '选择时间' : _selectedTime!.format(context)),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: _selectTime,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('时长:'),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _duration,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('开放式')),
                        DropdownMenuItem(value: 30, child: Text('30分钟')),
                        DropdownMenuItem(value: 60, child: Text('1小时')),
                        DropdownMenuItem(value: 90, child: Text('1.5小时')),
                        DropdownMenuItem(value: 120, child: Text('2小时')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _duration = value!;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isCreating ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _isCreating || _selectedTime == null ? null : _createAppointment,
          child: _isCreating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('创建'),
        ),
      ],
    );
  }

  /// 选择时间
  void _selectTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (time != null) {
      setState(() {
        _selectedTime = time;
      });
    }
  }

  /// 创建预约
  void _createAppointment() async {
    if (!_formKey.currentState!.validate() || _selectedTime == null) return;

    setState(() => _isCreating = true);

    final selectedDate = context.read<AppointmentProvider>().selectedDate;
    final startTime = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );

    final success = await context.read<AppointmentProvider>().createAppointment(
      startTime: startTime,
      duration: _duration,
      name: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
      recordNumber: _recordNumberController.text.trim().isEmpty ? null : _recordNumberController.text.trim(),
      type: _typeController.text.trim().isEmpty ? null : _typeController.text.trim(),
    );

    setState(() => _isCreating = false);

    if (success && mounted) {
      Navigator.pop(context);
    }
  }
}