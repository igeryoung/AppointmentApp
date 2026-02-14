import 'package:flutter/material.dart';
import '../../models/book.dart';
import 'book_list_state.dart';
import 'adapters/adapters.dart';
import 'utils/snackbar_utils.dart';
import 'dialogs/create_book_dialog.dart';
import 'dialogs/rename_book_dialog.dart';
import 'dialogs/archive_book_confirm_dialog.dart';
import 'dialogs/delete_book_confirm_dialog.dart';
import 'dialogs/import_server_book_dialog.dart';
import 'dialogs/server_settings_dialog.dart';
import '../../l10n/app_localizations.dart';
import '../../services/api_client.dart';
import '../../services/service_locator.dart';

/// Controller for BookListScreen
/// Handles all business logic and state management
class BookListController extends ChangeNotifier {
  final BookRepository repo;
  final BookOrderAdapter order;
  final ServerConfigAdapter serverConfig;
  final DeviceRegistrationAdapter deviceReg;

  BookListState _state = BookListState.initial();
  BookListState get state => _state;

  BookListController({
    required this.repo,
    required this.order,
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

      _setState(
        _state.copyWith(
          books: orderedBooks,
          isLoading: false,
          errorMessage: null,
        ),
      );
    } catch (e) {
      _setState(
        _state.copyWith(
          isLoading: false,
          errorMessage: 'Error loading books: $e',
        ),
      );
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

    try {
      // Create book on server and locally (server is the source of truth)
      await repo.create(name);
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
        SnackBarUtils.showError(context, l10n.errorArchivingBook(e.toString()));
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

  /// Show server import flow
  Future<void> openImportFromServerFlow(BuildContext context) async {
    _setState(_state.copyWith(isLoading: true));
    try {
      final serverBooks = await repo.listServerBooks();
      _setState(_state.copyWith(isLoading: false, errorMessage: null));

      if (serverBooks.isEmpty) {
        if (context.mounted) {
          SnackBarUtils.showInfo(context, 'No server books available');
        }
        return;
      }

      if (context.mounted) {
        final selectedBookUuid = await ImportServerBookDialog.show(
          context,
          books: serverBooks,
        );

        if (selectedBookUuid != null && selectedBookUuid.isNotEmpty) {
          await _importBookFromServer(context, selectedBookUuid);
        }
      }
    } catch (e) {
      final message = _buildImportErrorMessage(e);
      _setState(_state.copyWith(isLoading: false, errorMessage: message));
      if (context.mounted) {
        SnackBarUtils.showError(context, message);
      }
    }
  }

  /// Import book from server
  Future<void> _importBookFromServer(
    BuildContext context,
    String bookUuid,
  ) async {
    _setState(_state.copyWith(isLoading: true));
    try {
      await repo.pullBookFromServer(bookUuid);

      // Refresh the book list to show imported data
      await _loadBooks();

      if (context.mounted) {
        SnackBarUtils.showSuccess(context, 'Book imported successfully');
      }
    } catch (e) {
      _setState(
        _state.copyWith(
          isLoading: false,
          errorMessage: 'Failed to import book: $e',
        ),
      );
      if (context.mounted) {
        SnackBarUtils.showError(context, 'Failed to import book: $e');
      }
    }
  }

  String _buildImportErrorMessage(Object error) {
    if (error is ApiException) {
      final code = error.statusCode;
      if (code == 404) {
        return 'Import failed: /api/books not found on server. Update/restart server and verify URL in Server Settings.';
      }
      if (code == 401 || code == 403) {
        return 'Import failed: device credentials are invalid. Re-register this device in server setup.';
      }
    }
    return 'Failed to load server books: $error';
  }

  /// Clear current error state.
  void clearError() {
    _setState(_state.clearError());
  }

  /// Show server settings flow
  Future<void> openServerSettingsFlow(BuildContext context) async {
    final currentUrl = await serverConfig.getUrlOrDefault();

    if (!context.mounted) return;

    final newUrl = await ServerSettingsDialog.show(
      context,
      currentUrl: currentUrl,
    );

    if (newUrl != null && newUrl.isNotEmpty) {
      try {
        await serverConfig.setUrl(newUrl);

        // Recreate ApiClient with new URL and re-register services
        final apiClient = ApiClient(baseUrl: newUrl);
        await registerContentServices(apiClient);

        if (context.mounted) {
          SnackBarUtils.showSuccess(context, 'Server URL updated to: $newUrl');
        }
      } catch (e) {
        if (context.mounted) {
          SnackBarUtils.showError(context, 'Failed to update server URL: $e');
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
