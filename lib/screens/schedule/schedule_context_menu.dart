import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/event.dart';

/// Context menu overlay for event actions
class ScheduleContextMenu extends StatelessWidget {
  final Event event;
  final Offset position;
  final VoidCallback onClose;
  final VoidCallback onChangeType;
  final VoidCallback onChangeTime;
  final VoidCallback onScheduleNextAppointment;
  final VoidCallback onRemove;
  final VoidCallback onDelete;

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
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final screenSize = MediaQuery.of(context).size;

    // Determine if menu should appear above or below
    final showAbove = position.dy > screenSize.height / 2;

    return Positioned(
      left: position.dx.clamp(20.0, screenSize.width - 200),
      top: showAbove ? null : position.dy + 10,
      bottom: showAbove ? screenSize.height - position.dy + 10 : null,
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        event.name.isEmpty ? l10n.eventOptions : event.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: onClose,
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
                onTap: onChangeType,
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.access_time, size: 20),
                title: Text(l10n.changeEventTime, style: const TextStyle(fontSize: 14)),
                onTap: onChangeTime,
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.event_available, size: 20),
                title: Text(l10n.scheduleNextAppointment, style: const TextStyle(fontSize: 14)),
                onTap: onScheduleNextAppointment,
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.remove_circle_outline, color: Colors.orange, size: 20),
                title: Text(
                  l10n.removeEvent,
                  style: const TextStyle(color: Colors.orange, fontSize: 14),
                ),
                onTap: onRemove,
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.delete, color: Colors.red, size: 20),
                title: Text(
                  l10n.deleteEvent,
                  style: const TextStyle(color: Colors.red, fontSize: 14),
                ),
                onTap: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
