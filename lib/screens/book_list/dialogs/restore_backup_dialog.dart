import 'package:flutter/material.dart';
import '../utils/date_format_utils.dart';

/// Dialog for selecting a backup to restore
/// Returns the backup ID if selected, null if cancelled
class RestoreBackupDialog extends StatelessWidget {
  final List<Map<String, dynamic>> backups;

  const RestoreBackupDialog({
    super.key,
    required this.backups,
  });

  /// Show the dialog and return the selected backup ID
  static Future<int?> show(
    BuildContext context, {
    required List<Map<String, dynamic>> backups,
  }) {
    return showDialog<int>(
      context: context,
      builder: (context) => RestoreBackupDialog(backups: backups),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Restore Book from Server'),
      content: SizedBox(
        width: double.maxFinite,
        child: backups.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('No backups available'),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: backups.length,
                itemBuilder: (context, index) {
                  final backup = backups[index];
                  return _buildBackupCard(context, backup);
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildBackupCard(BuildContext context, Map<String, dynamic> backup) {
    final backupId = backup['id'] as int;
    final bookUuid = backup['bookUuid'] as String?;
    final backupName = backup['backupName'] as String;
    final createdAt = DateTime.parse(backup['createdAt'] as String);
    final backupSize = backup['backupSize'] as int;
    final restoredAt = backup['restoredAt'] as String?;
    final deviceId = backup['deviceId'] as String?;

    return Card(
      child: ListTile(
        leading: Icon(
          Icons.cloud_download,
          color: Theme.of(context).primaryColor,
          size: 32,
        ),
        title: Text(
          backupName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            if (bookUuid != null)
              Text(
                'Book UUID: ${bookUuid.substring(0, 8)}...',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            if (deviceId != null)
              Text(
                'Device: ${deviceId.substring(0, 8)}...',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            Text('Backup date: ${DateFormatUtils.formatDateTimeWithTime(createdAt, context)}'),
            Text('Size: ${(backupSize / 1024).toStringAsFixed(1)} KB'),
            if (restoredAt != null)
              Text(
                'Last restored: ${DateFormatUtils.formatDateTimeWithTime(DateTime.parse(restoredAt), context)}',
                style: const TextStyle(color: Colors.green, fontSize: 12),
              ),
          ],
        ),
        trailing: const Icon(Icons.download),
        onTap: () => Navigator.pop(context, backupId),
      ),
    );
  }
}
