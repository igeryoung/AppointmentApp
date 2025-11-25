import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/book.dart';
import 'book_list_state.dart';
import 'adapters/adapters.dart';
import 'utils/snackbar_utils.dart';
import 'dialogs/create_book_dialog.dart';
import 'dialogs/rename_book_dialog.dart';
import 'dialogs/archive_book_confirm_dialog.dart';
import 'dialogs/delete_book_confirm_dialog.dart';
import 'dialogs/restore_backup_dialog.dart';
import 'dialogs/server_settings_dialog.dart';
import '../../l10n/app_localizations.dart';

/// Controller for BookListScreen
/// Handles all business logic and state management
class BookListController extends ChangeNotifier {
  final BookRepository repo;
  final BookOrderAdapter order;
  final BookBackupAdapter backup;
  final ServerConfigAdapter serverConfig;
  final DeviceRegistrationAdapter deviceReg;

  BookListState _state = BookListState.initial();
  BookListState get state => _state;

  BookListController({
    required this.repo,
    required this.order,
    required this.backup,
    required this.serverConfig,
    required this.deviceReg,
  });

  /// Initialize controller and load books
  Future<void> initialize() async {
    await _loadBooks();
  }

  /// Reload books from database
  Future<void> reload() async {
    await _loadBooks();
  }

  /// Load books from database and apply saved order
  Future<void> _loadBooks() async {
    _setState(_state.copyWith(isLoading: true));
    try {
      final books = await repo.getAll();
      final savedOrder = await order.loadOrder();
      final orderedBooks = order.applyOrder(books, savedOrder);

      _setState(_state.copyWith(
        books: orderedBooks,
        isLoading: false,
        errorMessage: null,
      ));
    } catch (e) {
      _setState(_state.copyWith(
        isLoading: false,
        errorMessage: 'Error loading books: $e',
      ));
    }
  }

  /// Show create book dialog and create book if confirmed
  Future<void> promptCreate(BuildContext context) async {
    final name = await CreateBookDialog.show(context);
    if (name != null && name.isNotEmpty) {
      await createBook(context: context, name: name);
    }
  }

  /// Create a new book
  Future<void> createBook({
    required BuildContext context,
    required String name,
  }) async {
    _setState(_state.copyWith(isLoading: true));
    Book? createdBook;

    try {
      // Step 1: Create book on server and get UUID
      await repo.create(name);

      // Step 2: Get the newly created book
      createdBook = await repo.getByName(name);

      // Step 3: Upload book backup to server (REQUIRED - must succeed)
      if (createdBook != null && backup.available && createdBook.uuid.isNotEmpty) {
        try {
          await backup.upload(createdBook.uuid);
          debugPrint('✅ Book "${createdBook.name}" created and registered on server');
        } catch (uploadError) {
          debugPrint('❌ Failed to upload book backup: $uploadError');
          // ROLLBACK: Delete the local book since server sync failed
          await repo.delete(createdBook.uuid);
          debugPrint('🔄 Rolled back local book creation due to server sync failure');
          throw Exception('Server sync failed: $uploadError');
        }
      }

      await _loadBooks();
    } catch (e) {
      _setState(_state.copyWith(isLoading: false));
      if (context.mounted) {
        final l10n = AppLocalizations.of(context)!;
        SnackBarUtils.showError(context, l10n.errorCreatingBook(e.toString()));
      }
    }
  }

  /// Show rename dialog and rename book if confirmed
  Future<void> promptRename(BuildContext context, Book book) async {
    final newName = await RenameBookDialog.show(context, book: book);
    if (newName != null && newName != book.name) {
      await renameBook(context: context, book: book, newName: newName);
    }
  }

  /// Rename a book
  Future<void> renameBook({
    required BuildContext context,
    required Book book,
    required String newName,
  }) async {
    _setState(_state.copyWith(isLoading: true));
    try {
      await repo.update(book.copyWith(name: newName));
      await _loadBooks();
    } catch (e) {
      _setState(_state.copyWith(isLoading: false));
      if (context.mounted) {
        final l10n = AppLocalizations.of(context)!;
        SnackBarUtils.showError(context, l10n.errorUpdatingBook(e.toString()));
      }
    }
  }

  /// Show archive confirmation and archive book if confirmed
  Future<void> promptArchive(BuildContext context, Book book) async {
    final confirmed = await ArchiveBookConfirmDialog.show(context, book: book);
    if (confirmed == true) {
      await archiveBook(context: context, book: book);
    }
  }

  /// Archive a book
  Future<void> archiveBook({
    required BuildContext context,
    required Book book,
  }) async {
    _setState(_state.copyWith(isLoading: true));
    try {
      await repo.archive(book.uuid);
      await _loadBooks();
    } catch (e) {
      _setState(_state.copyWith(isLoading: false));
      if (context.mounted) {
        final l10n = AppLocalizations.of(context)!;
        SnackBarUtils.showError(
            context, l10n.errorArchivingBook(e.toString()));
      }
    }
  }

  /// Show delete confirmation and delete book if confirmed
  Future<void> promptDelete(BuildContext context, Book book) async {
    final confirmed = await DeleteBookConfirmDialog.show(context, book: book);
    if (confirmed == true) {
      await deleteBook(context: context, book: book);
    }
  }

  /// Delete a book
  Future<void> deleteBook({
    required BuildContext context,
    required Book book,
  }) async {
    _setState(_state.copyWith(isLoading: true));
    try {
      await repo.delete(book.uuid);
      await _loadBooks();
    } catch (e) {
      _setState(_state.copyWith(isLoading: false));
      if (context.mounted) {
        final l10n = AppLocalizations.of(context)!;
        SnackBarUtils.showError(context, l10n.errorDeletingBook(e.toString()));
      }
    }
  }

  /// Handle book reordering
  Future<void> reorderBooks(int oldIndex, int newIndex) async {
    // Adjust newIndex if moving down the list
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    // Reorder the books list
    final books = List<Book>.from(_state.books);
    final book = books.removeAt(oldIndex);
    books.insert(newIndex, book);

    // Update state immediately for smooth UX
    _setState(_state.copyWith(books: books));

    // Save the new order
    await order.saveCurrentOrder(books);
  }

  /// Upload a book to server
  Future<void> uploadToServer(BuildContext context, Book book) async {
    if (!backup.available) {
      if (context.mounted) {
        SnackBarUtils.showWarning(
            context, 'Book backup is not available on web');
      }
      return;
    }

    if (book.uuid.isEmpty) return;

    _setState(_state.copyWith(isLoading: true));
    try {
      final backupId = await backup.upload(book.uuid);
      _setState(_state.copyWith(isLoading: false));

      if (context.mounted) {
        SnackBarUtils.showSuccess(
          context,
          'Book "${book.name}" uploaded successfully (Backup ID: $backupId)',
        );
      }
    } catch (e) {
      _setState(_state.copyWith(isLoading: false));
      if (context.mounted) {
        SnackBarUtils.showError(context, 'Failed to upload book: $e');
      }
    }
  }

  /// Auto-register newly created book on server (runs in background)
  Future<void> _autoRegister(BuildContext context, Book book) async {
    // Skip if backup not available
    if (!backup.available || book.uuid.isEmpty) {
      return;
    }

    // Run upload in background without blocking UI
    try {
      await backup.upload(book.uuid);
      debugPrint('✅ Book "${book.name}" auto-registered on server');
    } catch (e) {
      debugPrint('⚠️  Failed to auto-register book on server: $e');
      // Show warning to user but don't block the flow
      if (context.mounted) {
        SnackBarUtils.showWarningWithAction(
          context: context,
          message:
              'Book created locally but not registered on server. You can upload it manually later.',
          actionLabel: 'Upload Now',
          onAction: () => uploadToServer(context, book),
        );
      }
    }
  }

  /// Show restore backup flow
  Future<void> openRestoreFlow(BuildContext context) async {
    if (!backup.available) {
      if (context.mounted) {
        SnackBarUtils.showWarning(
            context, 'Book backup is not available on web');
      }
      return;
    }

    _setState(_state.copyWith(isLoading: true));
    try {
      final backups = await backup.listBackups();
      _setState(_state.copyWith(isLoading: false));

      if (backups.isEmpty) {
        if (context.mounted) {
          SnackBarUtils.showInfo(context, 'No backups available');
        }
        return;
      }

      if (context.mounted) {
        final selectedBackupId =
            await RestoreBackupDialog.show(context, backups: backups);

        if (selectedBackupId != null) {
          await _restoreBookFromServer(context, selectedBackupId);
        }
      }
    } catch (e) {
      _setState(_state.copyWith(isLoading: false));
      if (context.mounted) {
        SnackBarUtils.showError(context, 'Failed to load backups: $e');
      }
    }
  }

  /// Restore book from server
  Future<void> _restoreBookFromServer(
      BuildContext context, int backupId) async {
    _setState(_state.copyWith(isLoading: true));
    try {
      final message = await backup.restore(backupId);

      // Refresh the book list to show the restored book
      await _loadBooks();

      if (context.mounted) {
        SnackBarUtils.showSuccess(context, message);
      }
    } catch (e) {
      _setState(_state.copyWith(isLoading: false));
      if (context.mounted) {
        SnackBarUtils.showError(context, 'Failed to restore book: $e');
      }
    }
  }

  /// Show server settings flow
  Future<void> openServerSettingsFlow(BuildContext context) async {
    if (!backup.available) return;

    final currentUrl = await serverConfig.getUrlOrDefault();

    if (!context.mounted) return;

    final newUrl = await ServerSettingsDialog.show(
      context,
      currentUrl: currentUrl,
    );

    if (newUrl != null && newUrl.isNotEmpty) {
      try {
        await serverConfig.setUrl(newUrl);
        if (context.mounted) {
          SnackBarUtils.showSuccess(
              context, 'Server URL updated to: $newUrl');
        }
      } catch (e) {
        if (context.mounted) {
          SnackBarUtils.showError(
              context, 'Failed to update server URL: $e');
        }
      }
    }
  }

  /// Update state and notify listeners
  void _setState(BookListState newState) {
    _state = newState;
    notifyListeners();
  }
}
