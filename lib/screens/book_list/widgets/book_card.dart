import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/book.dart';
import '../utils/date_format_utils.dart';

/// Pure UI widget for displaying a single book card
/// All actions are passed via callbacks
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
    final l10n = AppLocalizations.of(context)!;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: _buildLeadingIcon(context),
        title: _buildTitle(context),
        subtitle: _buildSubtitle(context, l10n),
        trailing: _buildPopupMenu(context, l10n),
        onTap: book.isArchived ? null : onTap,
      ),
    );
  }

  Widget _buildLeadingIcon(BuildContext context) {
    return Container(
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
    );
  }

  Widget _buildTitle(BuildContext context) {
    return Text(
      book.name,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            decoration: book.isArchived ? TextDecoration.lineThrough : null,
            color: book.isArchived ? Colors.grey : null,
          ),
    );
  }

  Widget _buildSubtitle(BuildContext context, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${l10n.createdLabel}${DateFormatUtils.formatDate(book.createdAt, context)}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
        ),
        if (book.isArchived && book.archivedAt != null)
          Text(
            '${l10n.archivedLabel}${DateFormatUtils.formatDate(book.archivedAt!, context)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[500],
                ),
          ),
      ],
    );
  }

  Widget _buildPopupMenu(BuildContext context, AppLocalizations l10n) {
    return PopupMenuButton<String>(
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
              title: Text(l10n.rename),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (!book.isArchived)
          PopupMenuItem(
            value: 'archive',
            child: ListTile(
              leading: const Icon(Icons.archive),
              title: Text(l10n.archive),
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
            title: Text(
              l10n.delete,
              style: const TextStyle(color: Colors.red),
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}
