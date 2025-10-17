import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/appointment_provider.dart';
import '../models/appointment.dart';
import '../widgets/handwriting_canvas.dart';

/// 预约详情屏幕 - 显示预约信息和手写笔记
class AppointmentDetailScreen extends StatefulWidget {
  const AppointmentDetailScreen({super.key});

  @override
  State<AppointmentDetailScreen> createState() => _AppointmentDetailScreenState();
}

class _AppointmentDetailScreenState extends State<AppointmentDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppointmentProvider>(
      builder: (context, appointmentProvider, child) {
        final appointment = appointmentProvider.currentAppointment;

        if (appointment == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('预约详情')),
            body: const Center(
              child: Text('预约不存在'),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(appointment.name ?? '预约详情'),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => _showEditDialog(context, appointment),
              ),
              PopupMenuButton<String>(
                onSelected: (value) => _handleMenuAction(context, value, appointment),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete, color: Colors.red),
                      title: Text('删除', style: TextStyle(color: Colors.red)),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.info), text: '详情'),
                Tab(icon: Icon(Icons.edit), text: '笔记'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _AppointmentInfo(appointment: appointment),
              _HandwritingNotes(appointment: appointment),
            ],
          ),
        );
      },
    );
  }

  /// 处理菜单操作
  void _handleMenuAction(BuildContext context, String action, Appointment appointment) {
    switch (action) {
      case 'delete':
        _showDeleteConfirmDialog(context, appointment);
        break;
    }
  }

  /// 显示编辑对话框
  void _showEditDialog(BuildContext context, Appointment appointment) {
    showDialog(
      context: context,
      builder: (context) => _EditAppointmentDialog(appointment: appointment),
    );
  }

  /// 显示删除确认对话框
  void _showDeleteConfirmDialog(BuildContext context, Appointment appointment) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除预约'),
        content: Text('确定要删除"${appointment.name ?? '无标题预约'}"吗？\n删除后将无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // 关闭对话框
              _deleteAppointment(context, appointment.id!);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  /// 删除预约
  void _deleteAppointment(BuildContext context, int appointmentId) async {
    final success = await context.read<AppointmentProvider>().deleteAppointment(appointmentId);
    if (success && mounted) {
      Navigator.pop(context); // 返回上一页
    }
  }
}

/// 预约信息组件
class _AppointmentInfo extends StatelessWidget {
  final Appointment appointment;

  const _AppointmentInfo({required this.appointment});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoCard(
            title: '基本信息',
            children: [
              _InfoRow(
                label: '预约名称',
                value: appointment.name ?? '无标题',
              ),
              _InfoRow(
                label: '记录编号',
                value: appointment.recordNumber ?? '无',
              ),
              _InfoRow(
                label: '预约类型',
                value: appointment.type ?? '无',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _InfoCard(
            title: '时间信息',
            children: [
              _InfoRow(
                label: '开始时间',
                value: DateFormat('yyyy年M月d日 HH:mm').format(appointment.startTime),
              ),
              _InfoRow(
                label: '结束时间',
                value: appointment.isOpenEnded
                    ? '开放式'
                    : DateFormat('HH:mm').format(appointment.endTime!),
              ),
              _InfoRow(
                label: '时长',
                value: appointment.isOpenEnded
                    ? '开放式'
                    : '${appointment.duration}分钟',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _InfoCard(
            title: '创建信息',
            children: [
              _InfoRow(
                label: '创建时间',
                value: DateFormat('yyyy年M月d日 HH:mm').format(appointment.createdAt),
              ),
              _InfoRow(
                label: '更新时间',
                value: DateFormat('yyyy年M月d日 HH:mm').format(appointment.updatedAt),
              ),
              _InfoRow(
                label: '笔记状态',
                value: appointment.noteStrokes.isEmpty ? '无笔记' : '有笔记 (${appointment.noteStrokes.length}笔)',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 信息卡片组件
class _InfoCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _InfoCard({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// 信息行组件
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// 手写笔记组件
class _HandwritingNotes extends StatefulWidget {
  final Appointment appointment;

  const _HandwritingNotes({required this.appointment});

  @override
  State<_HandwritingNotes> createState() => _HandwritingNotesState();
}

class _HandwritingNotesState extends State<_HandwritingNotes> {
  late HandwritingController _handwritingController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _handwritingController = HandwritingController(
      initialStrokes: widget.appointment.noteStrokes,
    );
  }

  @override
  void dispose() {
    _handwritingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 工具栏
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            border: Border(
              bottom: BorderSide(color: Colors.grey[300]!),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.undo),
                onPressed: _handwritingController.canUndo
                    ? () => _handwritingController.undo()
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.redo),
                onPressed: _handwritingController.canRedo
                    ? () => _handwritingController.redo()
                    : null,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () => _showClearConfirmDialog(),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveNotes,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: const Text('保存'),
              ),
            ],
          ),
        ),
        // 手写画布
        Expanded(
          child: HandwritingCanvas(
            controller: _handwritingController,
          ),
        ),
      ],
    );
  }

  /// 显示清空确认对话框
  void _showClearConfirmDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空笔记'),
        content: const Text('确定要清空所有笔记吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _handwritingController.clear();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }

  /// 保存笔记
  void _saveNotes() async {
    setState(() => _isSaving = true);

    final success = await context.read<AppointmentProvider>().updateAppointmentNotes(
      widget.appointment.id!,
      _handwritingController.strokes,
    );

    setState(() => _isSaving = false);

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('笔记保存成功')),
      );
    }
  }
}

/// 编辑预约对话框
class _EditAppointmentDialog extends StatefulWidget {
  final Appointment appointment;

  const _EditAppointmentDialog({required this.appointment});

  @override
  State<_EditAppointmentDialog> createState() => _EditAppointmentDialogState();
}

class _EditAppointmentDialogState extends State<_EditAppointmentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _recordNumberController;
  late final TextEditingController _typeController;

  late TimeOfDay _selectedTime;
  late int _duration;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    final appointment = widget.appointment;

    _nameController = TextEditingController(text: appointment.name ?? '');
    _recordNumberController = TextEditingController(text: appointment.recordNumber ?? '');
    _typeController = TextEditingController(text: appointment.type ?? '');

    _selectedTime = TimeOfDay.fromDateTime(appointment.startTime);
    _duration = appointment.duration;
  }

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
      title: const Text('编辑预约'),
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
                title: Text(_selectedTime.format(context)),
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
          onPressed: _isUpdating ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _isUpdating ? null : _updateAppointment,
          child: _isUpdating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }

  /// 选择时间
  void _selectTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );

    if (time != null) {
      setState(() {
        _selectedTime = time;
      });
    }
  }

  /// 更新预约
  void _updateAppointment() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isUpdating = true);

    final originalStartTime = widget.appointment.startTime;
    final newStartTime = DateTime(
      originalStartTime.year,
      originalStartTime.month,
      originalStartTime.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    final updatedAppointment = widget.appointment.copyWith(
      name: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
      recordNumber: _recordNumberController.text.trim().isEmpty ? null : _recordNumberController.text.trim(),
      type: _typeController.text.trim().isEmpty ? null : _typeController.text.trim(),
      startTime: newStartTime,
      duration: _duration,
    );

    final success = await context.read<AppointmentProvider>().updateAppointment(updatedAppointment);

    setState(() => _isUpdating = false);

    if (success && mounted) {
      Navigator.pop(context);
    }
  }
}