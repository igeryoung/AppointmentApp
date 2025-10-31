import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../models/book.dart';
import '../services/database_service_interface.dart';
import '../services/prd_database_service.dart';
import '../services/web_prd_database_service.dart';
import '../services/book_backup_service.dart';
import '../services/server_config_service.dart';
import '../services/book_order_service.dart';
import '../services/api_client.dart';
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
  final _bookOrderService = BookOrderService();

  // Use appropriate database service based on platform
  IDatabaseService get _dbService => kIsWeb
      ? WebPRDDatabaseService()
      : PRDDatabaseService();

  // Book backup service (mobile only)
  BookBackupService? get _backupService => kIsWeb
      ? null
      : BookBackupService(
          dbService: _dbService as PRDDatabaseService,
        );

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  Future<void> _loadBooks() async {
    setState(() => _isLoading = true);
    try {
      final books = await _dbService.getAllBooks();

      // Apply custom order from SharedPreferences
      final savedOrder = await _bookOrderService.loadBookOrder();
      final orderedBooks = _bookOrderService.applyOrder(books, savedOrder);

      setState(() {
        _books = orderedBooks;
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

        // Get the newly created book to auto-register it on server
        final books = await _dbService.getAllBooks();
        final newBook = books.firstWhere(
          (book) => book.name == result,
          orElse: () => books.last, // Fallback to most recent book
        );

        // Auto-register book on server (non-blocking)
        _autoRegisterBookOnServer(newBook);

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

  /// Handle book reordering
  Future<void> _onReorderBooks(int oldIndex, int newIndex) async {
    setState(() {
      // Adjust newIndex if moving down the list
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }

      // Reorder the books list
      final book = _books.removeAt(oldIndex);
      _books.insert(newIndex, book);
    });

    // Save the new order
    await _bookOrderService.saveCurrentOrder(_books);
  }

  void _openSchedule(Book book) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ScheduleScreen(book: book),
      ),
    );
  }

  Future<void> _uploadBookToServer(Book book) async {
    if (_backupService == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Book backup is not available on web')),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final backupId = await _backupService!.uploadBook(book.id!);
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Book "${book.name}" uploaded successfully (Backup ID: $backupId)')),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload book: $e')),
        );
      }
    }
  }

  /// Auto-register newly created book on server (runs in background)
  Future<void> _autoRegisterBookOnServer(Book book) async {
    // Skip if on web platform
    if (_backupService == null) {
      return;
    }

    // Run upload in background without blocking UI
    try {
      await _backupService!.uploadBook(book.id!);
      debugPrint('✅ Book "${book.name}" auto-registered on server');
    } catch (e) {
      debugPrint('⚠️  Failed to auto-register book on server: $e');
      // Show warning to user but don't block the flow
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Book created locally but not registered on server. You can upload it manually later.'),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.orange,
            action: SnackBarAction(
              label: 'Upload Now',
              textColor: Colors.white,
              onPressed: () => _uploadBookToServer(book),
            ),
          ),
        );
      }
    }
  }

  Future<void> _showRestoreDialog() async {
    if (_backupService == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Book backup is not available on web')),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final backups = await _backupService!.listBackups();
      setState(() => _isLoading = false);

      if (backups.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No backups available')),
          );
        }
        return;
      }

      if (mounted) {
        final selectedBackupId = await showDialog<int>(
          context: context,
          builder: (context) => _RestoreBackupDialog(backups: backups),
        );

        if (selectedBackupId != null) {
          _restoreBookFromServer(selectedBackupId);
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load backups: $e')),
        );
      }
    }
  }

  Future<void> _restoreBookFromServer(int backupId) async {
    setState(() => _isLoading = true);
    try {
      final message = await _backupService!.restoreBook(backupId);

      // Refresh the book list to show the restored book
      await _loadBooks();

      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to restore book: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showServerSettings() async {
    if (kIsWeb) return;

    final serverConfigService = ServerConfigService(_dbService as PRDDatabaseService);
    final currentUrl = await serverConfigService.getServerUrlOrDefault();

    if (!mounted) return;

    final newUrl = await showDialog<String>(
      context: context,
      builder: (context) => _ServerSettingsDialog(currentUrl: currentUrl),
    );

    if (newUrl != null && newUrl.isNotEmpty) {
      try {
        await serverConfigService.setServerUrl(newUrl);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Server URL updated to: $newUrl')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update server URL: $e')),
          );
        }
      }
    }
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
          // Restore from Server
          if (!kIsWeb)
            IconButton(
              icon: const Icon(Icons.cloud_download),
              tooltip: 'Restore from Server',
              onPressed: _showRestoreDialog,
            ),
          // Server Settings
          if (!kIsWeb)
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Server Settings',
              onPressed: _showServerSettings,
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
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _books.length,
      onReorder: _onReorderBooks,
      proxyDecorator: (child, index, animation) {
        // Customize the appearance of the dragged item
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            return Material(
              elevation: 8.0,
              shadowColor: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
              child: child,
            );
          },
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final book = _books[index];
        return _BookCard(
          key: ValueKey(book.uuid), // Important: key is required for ReorderableListView
          book: book,
          onTap: () => _openSchedule(book),
          onRename: () => _renameBook(book),
          onArchive: () => _archiveBook(book),
          onDelete: () => _deleteBook(book),
          onUploadToServer: kIsWeb ? null : () => _uploadBookToServer(book),
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
  final VoidCallback? onUploadToServer;

  const _BookCard({
    super.key, // Add key parameter for ReorderableListView
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

/// Restore Backup Dialog
class _RestoreBackupDialog extends StatelessWidget {
  final List<Map<String, dynamic>> backups;

  const _RestoreBackupDialog({required this.backups});

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
                  final backupId = backup['id'] as int;
                  final bookUuid = backup['bookUuid'] as String?;
                  final backupName = backup['backupName'] as String;
                  final createdAt = DateTime.parse(backup['createdAt'] as String);
                  final backupSize = backup['backupSize'] as int;
                  final restoredAt = backup['restoredAt'] as String?;

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
                              'UUID: ${bookUuid.substring(0, 8)}...',
                              style: TextStyle(color: Colors.grey[600], fontSize: 12),
                            ),
                          Text('Backup date: ${DateFormat('MMM d, y HH:mm', Localizations.localeOf(context).toString()).format(createdAt)}'),
                          Text('Size: ${(backupSize / 1024).toStringAsFixed(1)} KB'),
                          if (restoredAt != null)
                            Text(
                              'Last restored: ${DateFormat('MMM d, y HH:mm', Localizations.localeOf(context).toString()).format(DateTime.parse(restoredAt))}',
                              style: const TextStyle(color: Colors.green, fontSize: 12),
                            ),
                        ],
                      ),
                      trailing: const Icon(Icons.download),
                      onTap: () => Navigator.pop(context, backupId),
                    ),
                  );
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

/// Server Settings Dialog - Two-step flow with registration
class _ServerSettingsDialog extends StatefulWidget {
  final String currentUrl;

  const _ServerSettingsDialog({required this.currentUrl});

  @override
  State<_ServerSettingsDialog> createState() => _ServerSettingsDialogState();
}

enum _DialogStep { urlInput, registration }

class _ServerSettingsDialogState extends State<_ServerSettingsDialog> {
  late final TextEditingController _urlController;
  late final TextEditingController _passwordController;
  final _formKey = GlobalKey<FormState>();

  _DialogStep _currentStep = _DialogStep.urlInput;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.currentUrl);
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_currentStep == _DialogStep.urlInput ? 'Server Settings' : 'Device Registration'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_currentStep == _DialogStep.urlInput) ..._buildUrlStep()
            else ..._buildRegistrationStep(),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 14),
              ),
            ],
            if (_isLoading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
      actions: _buildActions(),
    );
  }

  List<Widget> _buildUrlStep() {
    return [
      const Text(
        'Configure the server URL for sync and backup operations.',
        style: TextStyle(fontSize: 14, color: Colors.grey),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _urlController,
        decoration: const InputDecoration(
          labelText: 'Server URL',
          hintText: 'http://192.168.1.100:8080',
          border: OutlineInputBorder(),
          helperText: 'Example: http://your-mac-ip:8080',
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Server URL is required';
          }
          final uri = Uri.tryParse(value.trim());
          if (uri == null || (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https'))) {
            return 'Invalid URL format (must start with http:// or https://)';
          }
          return null;
        },
        enabled: !_isLoading,
        autofocus: true,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.next,
      ),
    ];
  }

  List<Widget> _buildRegistrationStep() {
    return [
      const Text(
        'This device is not registered with the server. Please enter the registration password to continue.',
        style: TextStyle(fontSize: 14, color: Colors.grey),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _passwordController,
        decoration: const InputDecoration(
          labelText: 'Registration Password',
          hintText: 'Enter password',
          border: OutlineInputBorder(),
          helperText: 'Contact your server administrator for the password',
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Password is required';
          }
          return null;
        },
        enabled: !_isLoading,
        obscureText: true,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => _handleRegistration(),
      ),
    ];
  }

  List<Widget> _buildActions() {
    return [
      TextButton(
        onPressed: _isLoading ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      if (_currentStep == _DialogStep.urlInput)
        ElevatedButton(
          onPressed: _isLoading ? null : _handleUrlSubmit,
          child: const Text('Next'),
        )
      else
        ElevatedButton(
          onPressed: _isLoading ? null : _handleRegistration,
          child: const Text('Register'),
        ),
    ];
  }

  Future<void> _handleUrlSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final serverUrl = _urlController.text.trim();
      final dbService = PRDDatabaseService();

      // Check if device is already registered
      final credentials = await dbService.getDeviceCredentials();

      if (credentials != null) {
        // Device already registered, just save URL and close
        if (mounted) {
          Navigator.pop(context, serverUrl);
        }
        return;
      }

      // Device not registered, move to registration step
      setState(() {
        _currentStep = _DialogStep.registration;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error checking device registration: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _handleRegistration() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final serverUrl = _urlController.text.trim();
      final password = _passwordController.text.trim();
      final dbService = PRDDatabaseService();

      // Import dart:io to get platform info
      final platform = Theme.of(context).platform.name;
      final deviceName = '$platform Device';

      // Create API client and register device
      final apiClient = ApiClient(baseUrl: serverUrl);
      final response = await apiClient.registerDevice(
        deviceName: deviceName,
        password: password,
        platform: platform,
      );

      // Save device credentials
      final deviceId = response['deviceId'] as String;
      final deviceToken = response['deviceToken'] as String;
      await dbService.saveDeviceCredentials(
        deviceId: deviceId,
        deviceToken: deviceToken,
        deviceName: deviceName,
        platform: platform,
      );

      // Clean up and return URL
      apiClient.dispose();

      if (mounted) {
        Navigator.pop(context, serverUrl);
      }
    } catch (e) {
      setState(() {
        if (e.toString().contains('Invalid registration password')) {
          _errorMessage = 'Invalid password. Please try again.';
        } else {
          _errorMessage = 'Registration failed: $e';
        }
        _isLoading = false;
      });
    }
  }
}