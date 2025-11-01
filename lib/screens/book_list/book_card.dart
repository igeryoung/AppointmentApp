import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../l10n/app_localizations.dart';
import '../../models/book.dart';

/// Card widget for displaying a single book in the list
class BookCard extends StatelessWidget {
  final Book book;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onArchive;
  final VoidCallback onDelete;
  final VoidCallback? onUploadToServer;

  const BookCard({
    super.key,
    required this.book,
    required this.onTap,
    required this.onRename,
    required this.onArchive,
    required this.onDelete,
    this.onUploadToServer,
  });

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
            color: book.isArchived
                ? Colors.grey.withOpacity(0.3)
                : Theme.of(context).primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            book.isArchived ? Icons.archive : Icons.book,
            color: book.isArchived
                ? Colors.grey
                : Theme.of(context).primaryColor,
          ),
        ),
        title: Text(
          book.name,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            decoration: book.isArchived ? TextDecoration.lineThrough : null,
            color: book.isArchived ? Colors.grey : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${AppLocalizations.of(context)!.createdLabel}${DateFormat('MMM d, y', Localizations.localeOf(context).toString()).format(book.createdAt)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            if (book.isArchived)
              Text(
                '${AppLocalizations.of(context)!.archivedLabel}${DateFormat('MMM d, y', Localizations.localeOf(context).toString()).format(book.archivedAt!)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[500],
                ),
              ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'rename':
                onRename();
                break;
              case 'archive':
                onArchive();
                break;
              case 'upload':
                if (onUploadToServer != null) onUploadToServer!();
                break;
              case 'delete':
                onDelete();
                break;
            }
          },
          itemBuilder: (context) => [
            if (!book.isArchived)
              PopupMenuItem(
                value: 'rename',
                child: ListTile(
                  leading: const Icon(Icons.edit),
                  title: Text(AppLocalizations.of(context)!.rename),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            if (!book.isArchived)
              PopupMenuItem(
                value: 'archive',
                child: ListTile(
                  leading: const Icon(Icons.archive),
                  title: Text(AppLocalizations.of(context)!.archive),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            if (!book.isArchived && onUploadToServer != null)
              const PopupMenuItem(
                value: 'upload',
                child: ListTile(
                  leading: Icon(Icons.cloud_upload),
                  title: Text('Upload to Server'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: Text(AppLocalizations.of(context)!.delete, style: const TextStyle(color: Colors.red)),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
        onTap: book.isArchived ? null : onTap,
      ),
    );
  }
}
