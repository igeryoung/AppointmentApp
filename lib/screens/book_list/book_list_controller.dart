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
import 'dialogs/book_password_dialog.dart';
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
      try {
        await deviceReg.refreshDeviceRoleFromServer();
      } catch (_) {}
      final credentials = await deviceReg.getCredentials();
      final role = (credentials?['deviceRole'] as String?)?.toLowerCase();
      final isReadOnly = credentials?['isReadOnly'] == true || role == 'read';

      final books = await repo.getAll();
      final savedOrder = await order.loadOrder();
      final orderedBooks = order.applyOrder(books, savedOrder);

      _setState(
        _state.copyWith(
          books: orderedBooks,
          isLoading: false,
          isReadOnlyDevice: isReadOnly,
          errorMessage: null,
        ),
      );
    } catch (e) {
      _setState(
        _state.copyWith(
          isLoading: false,
          isReadOnlyDevice: false,
          errorMessage: '載入簿冊失敗：$e',
        ),
      );
    }
  }

  /// Show create book dialog and create book if confirmed
  Future<void> promptCreate(BuildContext context) async {
    if (_state.isReadOnlyDevice) {
      final l10n = AppLocalizations.of(context)!;
      SnackBarUtils.showInfo(context, l10n.readOnlyCreateBookDisabled);
      return;
    }
    final input = await CreateBookDialog.show(context);
    if (input != null && input.name.isNotEmpty) {
      await createBook(
        context: context,
        name: input.name,
        password: input.password,
      );
    }
  }

  /// Create a new book
  Future<void> createBook({
    required BuildContext context,
    required String name,
    required String password,
  }) async {
    _setState(_state.copyWith(isLoading: true));

    try {
      // Create book on server and locally (server is the source of truth)
      await repo.create(name, password: password);
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
    if (_state.isReadOnlyDevice) {
      final l10n = AppLocalizations.of(context)!;
      SnackBarUtils.showInfo(context, l10n.readOnlyRenameDisabled);
      return;
    }
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
    if (_state.isReadOnlyDevice) {
      final l10n = AppLocalizations.of(context)!;
      SnackBarUtils.showInfo(context, l10n.readOnlyArchiveDisabled);
      return;
    }
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
    if (_state.isReadOnlyDevice) {
      final l10n = AppLocalizations.of(context)!;
      SnackBarUtils.showInfo(context, l10n.readOnlyDeleteDisabled);
      return;
    }
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
    final l10n = AppLocalizations.of(context)!;
    _setState(_state.copyWith(isLoading: true));
    try {
      final serverBooks = await repo.listServerBooks();
      _setState(_state.copyWith(isLoading: false, errorMessage: null));

      if (serverBooks.isEmpty) {
        if (context.mounted) {
          SnackBarUtils.showInfo(context, l10n.noServerBooksAvailable);
        }
        return;
      }

      if (context.mounted) {
        final selectedBookUuid = await ImportServerBookDialog.show(
          context,
          books: serverBooks,
        );

        if (selectedBookUuid != null && selectedBookUuid.isNotEmpty) {
          final password = await BookPasswordDialog.show(
            context,
            title: l10n.enterBookPassword,
            description: l10n.importBookPasswordRequiredDescription,
          );
          if (password == null || password.isEmpty) {
            return;
          }
          await _importBookFromServer(
            context,
            selectedBookUuid,
            password: password,
          );
        }
      }
    } catch (e) {
      final message = _buildImportErrorMessage(e, l10n);
      _setState(_state.copyWith(isLoading: false, errorMessage: message));
      if (context.mounted) {
        SnackBarUtils.showError(context, message);
      }
    }
  }

  /// Import book from server
  Future<void> _importBookFromServer(
    BuildContext context,
    String bookUuid, {
    required String password,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    _setState(_state.copyWith(isLoading: true));
    try {
      await repo.pullBookFromServer(
        bookUuid,
        password: password,
        lightImport: true,
      );

      // Refresh the book list to show imported data
      await _loadBooks();

      if (context.mounted) {
        SnackBarUtils.showSuccess(context, l10n.bookImportedSuccessfully);
      }
    } catch (e) {
      final isPasswordError =
          _isInvalidBookPasswordError(e) || _isForbiddenImportError(e);
      final isAlreadyExistsError = _isBookAlreadyExistsError(e);
      final message = _buildImportErrorMessage(e, l10n);
      _setState(
        _state.copyWith(
          isLoading: false,
          errorMessage: (isPasswordError || isAlreadyExistsError)
              ? null
              : message,
        ),
      );
      if (context.mounted) {
        if (isPasswordError) {
          await showDialog<void>(
            context: context,
            builder: (dialogContext) {
              return AlertDialog(
                title: const Text('密碼錯誤'),
                content: const Text('您輸入的簿冊密碼不正確，請重新輸入後再試一次。'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('確定'),
                  ),
                ],
              );
            },
          );
          return;
        }
        if (isAlreadyExistsError) {
          await showDialog<void>(
            context: context,
            builder: (dialogContext) {
              return AlertDialog(
                title: const Text('簿冊已存在'),
                content: const Text('此簿冊已在本機，無法重複匯入。'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('確定'),
                  ),
                ],
              );
            },
          );
          return;
        }
        SnackBarUtils.showError(context, message);
      }
    }
  }

  bool _isInvalidBookPasswordError(Object error) {
    if (error is ApiException) {
      if (error.statusCode != 403) return false;
      final bodyText = (error.responseBody ?? '').toLowerCase();
      final messageText = error.message.toLowerCase();
      return bodyText.contains('invalid_book_password') ||
          bodyText.contains('book password') ||
          messageText.contains('book password');
    }
    final text = error.toString().toLowerCase();
    return text.contains('invalid_book_password') ||
        text.contains('invalid book password') ||
        text.contains('book password');
  }

  bool _isForbiddenImportError(Object error) {
    if (error is ApiException) {
      return error.statusCode == 403;
    }
    final text = error.toString().toLowerCase();
    return text.contains('403');
  }

  bool _isBookAlreadyExistsError(Object error) {
    if (error is ApiException) {
      if (error.statusCode == 409) return true;
      final bodyText = (error.responseBody ?? '').toLowerCase();
      final messageText = error.message.toLowerCase();
      return bodyText.contains('already exists') ||
          bodyText.contains('already exists locally') ||
          messageText.contains('already exists') ||
          messageText.contains('already exists locally');
    }
    final text = error.toString().toLowerCase();
    return text.contains('already exists') ||
        text.contains('already exists locally');
  }

  String _buildImportErrorMessage(Object error, AppLocalizations l10n) {
    if (_isBookAlreadyExistsError(error)) {
      return l10n.importFailedBookAlreadyExists;
    }
    if (_isInvalidBookPasswordError(error) || _isForbiddenImportError(error)) {
      return l10n.importFailedInvalidBookPassword;
    }
    if (error is ApiException) {
      final code = error.statusCode;
      if (code == 404) {
        return l10n.importFailedApiBooksNotFound;
      }
      if (code == 401 || code == 403) {
        return l10n.importFailedInvalidDeviceCredentials;
      }
    }
    return l10n.failedToLoadServerBooks(error.toString());
  }

  /// Clear current error state.
  void clearError() {
    _setState(_state.clearError());
  }

  /// Show server settings flow
  Future<void> openServerSettingsFlow(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
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
          SnackBarUtils.showSuccess(context, l10n.serverUrlUpdated(newUrl));
        }
      } catch (e) {
        if (context.mounted) {
          SnackBarUtils.showError(
            context,
            l10n.failedToUpdateServerUrl(e.toString()),
          );
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
