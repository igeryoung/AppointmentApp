import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../models/book.dart';
import '../services/prd_database_service.dart';
import '../services/web_prd_database_service.dart';
import 'schedule_screen.dart';

/// Book List Screen - Top-level containers as per PRD
class BookListScreen extends StatefulWidget {
  const BookListScreen({super.key});

  @override
  State<BookListScreen> createState() => _BookListScreenState();
}

class _BookListScreenState extends State<BookListScreen> {
  List<Book> _books = [];
  bool _isLoading = false;

  // Use appropriate database service based on platform
  dynamic get _dbService => kIsWeb
      ? WebPRDDatabaseService()
      : PRDDatabaseService();

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  Future<void> _loadBooks() async {
    setState(() => _isLoading = true);
    try {
      final books = await _dbService.getAllBooks();
      setState(() {
        _books = books;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.errorLoadingBooks(e.toString()))),
        );
      }
    }
  }

  Future<void> _createBook() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => const _CreateBookDialog(),
    );

    if (result != null && result.isNotEmpty) {
      setState(() => _isLoading = true);
      try {
        await _dbService.createBook(result);
        _loadBooks();
      } catch (e) {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.errorCreatingBook(e.toString()))),
          );
        }
      }
    }
  }

  Future<void> _renameBook(Book book) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _RenameBookDialog(book: book),
    );

    if (result != null && result != book.name) {
      setState(() => _isLoading = true);
      try {
        await _dbService.updateBook(book.copyWith(name: result));
        _loadBooks();
      } catch (e) {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.errorUpdatingBook(e.toString()))),
          );
        }
      }
    }
  }

  Future<void> _archiveBook(Book book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.archiveBook),
        content: Text(AppLocalizations.of(context)!.archiveBookConfirmation(book.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppLocalizations.of(context)!.archive),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        await _dbService.archiveBook(book.id!);
        _loadBooks();
      } catch (e) {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.errorArchivingBook(e.toString()))),
          );
        }
      }
    }
  }

  Future<void> _deleteBook(Book book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.deleteBook),
        content: Text(AppLocalizations.of(context)!.deleteBookConfirmation(book.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(AppLocalizations.of(context)!.delete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        await _dbService.deleteBook(book.id!);
        _loadBooks();
      } catch (e) {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.errorDeletingBook(e.toString()))),
          );
        }
      }
    }
  }

  void _openSchedule(Book book) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ScheduleScreen(book: book),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.appointmentBooks),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadBooks,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _books.isEmpty
              ? _buildEmptyState()
              : _buildBookList(),
      floatingActionButton: FloatingActionButton(
        onPressed: _createBook,
        child: const Icon(Icons.add),
        tooltip: AppLocalizations.of(context)!.createNewBook,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.book_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)!.noAppointmentBooks,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context)!.tapToCreateFirstBook,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _books.length,
      itemBuilder: (context, index) {
        final book = _books[index];
        return _BookCard(
          book: book,
          onTap: () => _openSchedule(book),
          onRename: () => _renameBook(book),
          onArchive: () => _archiveBook(book),
          onDelete: () => _deleteBook(book),
        );
      },
    );
  }
}

/// Book Card Widget
class _BookCard extends StatelessWidget {
  final Book book;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  const _BookCard({
    required this.book,
    required this.onTap,
    required this.onRename,
    required this.onArchive,
    required this.onDelete,
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
              '${AppLocalizations.of(context)!.createdLabel}${DateFormat('MMM d, y').format(book.createdAt)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            if (book.isArchived)
              Text(
                '${AppLocalizations.of(context)!.archivedLabel}${DateFormat('MMM d, y').format(book.archivedAt!)}',
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

/// Create Book Dialog
class _CreateBookDialog extends StatefulWidget {
  const _CreateBookDialog();

  @override
  State<_CreateBookDialog> createState() => _CreateBookDialogState();
}

class _CreateBookDialogState extends State<_CreateBookDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.createNewBook),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: l10n.bookName,
            hintText: l10n.enterBookName,
            border: const OutlineInputBorder(),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return l10n.bookNameRequired;
            }
            if (value.trim().length > 50) {
              return l10n.bookNameTooLong;
            }
            return null;
          },
          autofocus: true,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: Text(l10n.create),
        ),
      ],
    );
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, _controller.text.trim());
    }
  }
}

/// Rename Book Dialog
class _RenameBookDialog extends StatefulWidget {
  final Book book;

  const _RenameBookDialog({required this.book});

  @override
  State<_RenameBookDialog> createState() => _RenameBookDialogState();
}

class _RenameBookDialogState extends State<_RenameBookDialog> {
  late final TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.book.name);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.renameBook),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: l10n.bookName,
            border: const OutlineInputBorder(),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return l10n.bookNameRequired;
            }
            if (value.trim().length > 50) {
              return l10n.bookNameTooLong;
            }
            return null;
          },
          autofocus: true,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: Text(l10n.save),
        ),
      ],
    );
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, _controller.text.trim());
    }
  }
}