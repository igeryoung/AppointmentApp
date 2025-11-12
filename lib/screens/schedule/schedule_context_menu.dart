import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/event.dart';

/// Context menu overlay for event actions
class ScheduleContextMenu extends StatefulWidget {
  final Event event;
  final Offset position;
  final VoidCallback onClose;
  final VoidCallback onChangeType;
  final VoidCallback onChangeTime;
  final VoidCallback onScheduleNextAppointment;
  final VoidCallback onRemove;
  final VoidCallback onDelete;
  final Function(bool) onCheckedChanged;

  const ScheduleContextMenu({
    super.key,
    required this.event,
    required this.position,
    required this.onClose,
    required this.onChangeType,
    required this.onChangeTime,
    required this.onScheduleNextAppointment,
    required this.onRemove,
    required this.onDelete,
    required this.onCheckedChanged,
  });

  @override
  State<ScheduleContextMenu> createState() => _ScheduleContextMenuState();
}

class _ScheduleContextMenuState extends State<ScheduleContextMenu> {
  late bool isChecked;

  @override
  void initState() {
    super.initState();
    isChecked = widget.event.isChecked;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final screenSize = MediaQuery.of(context).size;

    // Determine if menu should appear above or below
    final showAbove = widget.position.dy > screenSize.height / 2;

    return Positioned(
      left: widget.position.dx.clamp(20.0, screenSize.width - 200),
      top: showAbove ? null : widget.position.dy + 10,
      bottom: showAbove ? screenSize.height - widget.position.dy + 10 : null,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 200,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                ),
                child: Row(
                  children: [
                    // Checkbox for marking event as completed
                    Transform.scale(
                      scale: 0.9,
                      child: Checkbox(
                        value: isChecked,
                        onChanged: (value) {
                          setState(() {
                            isChecked = value ?? false;
                          });
                          widget.onCheckedChanged(isChecked);
                        },
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    // Event name
                    Expanded(
                      child: Text(
                        widget.event.name.isEmpty ? l10n.eventOptions : widget.event.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Close button
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Menu items
              ListTile(
                dense: true,
                leading: const Icon(Icons.category, size: 20),
                title: Text(l10n.changeEventType, style: const TextStyle(fontSize: 14)),
                onTap: widget.onChangeType,
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.access_time, size: 20),
                title: Text(l10n.changeEventTime, style: const TextStyle(fontSize: 14)),
                onTap: widget.onChangeTime,
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.event_available, size: 20),
                title: Text(l10n.scheduleNextAppointment, style: const TextStyle(fontSize: 14)),
                onTap: widget.onScheduleNextAppointment,
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.remove_circle_outline, color: Colors.orange, size: 20),
                title: Text(
                  l10n.removeEvent,
                  style: const TextStyle(color: Colors.orange, fontSize: 14),
                ),
                onTap: widget.onRemove,
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.delete, color: Colors.red, size: 20),
                title: Text(
                  l10n.deleteEvent,
                  style: const TextStyle(color: Colors.red, fontSize: 14),
                ),
                onTap: widget.onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
