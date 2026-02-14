import 'package:flutter/material.dart';

import '../utils/date_format_utils.dart';

/// Dialog for selecting a server book to import.
/// Returns selected bookUuid, null if cancelled.
class ImportServerBookDialog extends StatelessWidget {
  final List<Map<String, dynamic>> books;

  const ImportServerBookDialog({super.key, required this.books});

  static Future<String?> show(
    BuildContext context, {
    required List<Map<String, dynamic>> books,
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => ImportServerBookDialog(books: books),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import Book from Server'),
      content: SizedBox(
        width: double.maxFinite,
        child: books.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('No server books available'),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: books.length,
                itemBuilder: (context, index) {
                  final book = books[index];
                  return _buildBookCard(context, book);
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

  Widget _buildBookCard(BuildContext context, Map<String, dynamic> book) {
    final bookUuid = (book['bookUuid'] ?? '').toString();
    final name = (book['name'] ?? '').toString();
    final createdAtRaw = book['createdAt'];
    final createdAt = createdAtRaw is String
        ? DateTime.tryParse(createdAtRaw)
        : null;
    final deviceId = book['deviceId']?.toString();

    return Card(
      child: ListTile(
        leading: Icon(
          Icons.cloud_download,
          color: Theme.of(context).primaryColor,
          size: 32,
        ),
        title: Text(
          name.isEmpty ? bookUuid : name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            if (bookUuid.isNotEmpty)
              Text(
                'Book UUID: ${bookUuid.substring(0, bookUuid.length >= 8 ? 8 : bookUuid.length)}...',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            if (deviceId != null && deviceId.isNotEmpty)
              Text(
                'Owner Device: ${deviceId.substring(0, deviceId.length >= 8 ? 8 : deviceId.length)}...',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            if (createdAt != null)
              Text(
                'Created: ${DateFormatUtils.formatDateTimeWithTime(createdAt, context)}',
              ),
          ],
        ),
        trailing: const Icon(Icons.download),
        onTap: () => Navigator.pop(context, bookUuid),
      ),
    );
  }
}
