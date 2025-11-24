import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../cubits/book_list_cubit.dart';
import '../../cubits/book_list_state.dart';
import '../../cubits/schedule_cubit.dart';
import '../../l10n/app_localizations.dart';
import '../../models/book.dart';
import '../../services/service_locator.dart';
import '../schedule_screen.dart';
import 'book_card.dart';
import 'create_book_dialog.dart';
import 'rename_book_dialog.dart';

/// Book List Screen - BLoC version
/// Displays all books and allows CRUD operations
class BookListScreenBloc extends StatelessWidget {
  const BookListScreenBloc({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<BookListCubit>()..loadBooks(),
      child: const _BookListView(),
    );
  }
}

class _BookListView extends StatelessWidget {
  const _BookListView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.appointmentBooks),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<BookListCubit>().loadBooks(),
          ),
          if (!kIsWeb)
            IconButton(
              icon: const Icon(Icons.cloud_download),
              tooltip: 'Restore from Server',
              onPressed: () => _showRestoreDialog(context),
            ),
          if (!kIsWeb)
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Server Settings',
              onPressed: () => _showServerSettings(context),
            ),
        ],
      ),
      body: BlocConsumer<BookListCubit, BookListState>(
        listener: (context, state) {
          // Show errors in snackbar
          if (state is BookListError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
          }
        },
        builder: (context, state) {
          if (state is BookListLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is BookListLoaded) {
            if (state.books.isEmpty) {
              return _buildEmptyState(context);
            }
            return _buildBookList(context, state.books);
          }

          // Initial or error state - show empty
          return _buildEmptyState(context);
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createBook(context),
        tooltip: AppLocalizations.of(context)!.createNewBook,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
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

  Widget _buildBookList(BuildContext context, List<Book> books) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: books.length,
      onReorder: (oldIndex, newIndex) {
        context.read<BookListCubit>().reorderBooks(oldIndex, newIndex);
      },
      proxyDecorator: (child, index, animation) {
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
        final book = books[index];
        return BookCard(
          key: ValueKey(book.uuid),
          book: book,
          onTap: () => _openSchedule(context, book),
          onRename: () => _renameBook(context, book),
          onArchive: () => _archiveBook(context, book),
          onDelete: () => _deleteBook(context, book),
          onUploadToServer: kIsWeb ? null : () => _uploadBookToServer(context, book),
        );
      },
    );
  }

  // ===================
  // Actions
  // ===================

  Future<void> _createBook(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => const CreateBookDialog(),
    );

    if (result != null && result.isNotEmpty && context.mounted) {
      final cubit = context.read<BookListCubit>();
      final newBook = await cubit.createBook(result);

      // Auto-register book on server (non-blocking)
      if (newBook != null && !kIsWeb && context.mounted) {
        _autoRegisterBookOnServer(context, newBook);
      }
    }
  }

  Future<void> _renameBook(BuildContext context, Book book) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => RenameBookDialog(book: book),
    );

    if (result != null && result != book.name && context.mounted) {
      context.read<BookListCubit>().updateBook(book, newName: result);
    }
  }

  Future<void> _archiveBook(BuildContext context, Book book) async {
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

    if (confirmed == true && context.mounted) {
      context.read<BookListCubit>().archiveBook(book.uuid);
    }
  }

  Future<void> _deleteBook(BuildContext context, Book book) async {
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

    if (confirmed == true && context.mounted) {
      context.read<BookListCubit>().deleteBook(book.uuid);
    }
  }

  void _openSchedule(BuildContext context, Book book) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BlocProvider(
          // Initialize cubit with book UUID
          create: (context) => getIt<ScheduleCubit>()..initialize(book.uuid),
          child: ScheduleScreen(book: book),
        ),
      ),
    );
  }

  Future<void> _uploadBookToServer(BuildContext context, Book book) async {
    // Note: This functionality remains as-is for now (not part of cubit)
    // TODO: Move to a dedicated BackupCubit in future refactoring
    debugPrint('Upload book to server: ${book.name}');
  }

  Future<void> _autoRegisterBookOnServer(BuildContext context, Book book) async {
    // Note: This functionality remains as-is for now (not part of cubit)
    // TODO: Move to a dedicated BackupCubit in future refactoring
    debugPrint('Auto-register book on server: ${book.name}');
  }

  Future<void> _showRestoreDialog(BuildContext context) async {
    // Note: Restore functionality kept as-is for now
    // TODO: Move to a dedicated BackupCubit in future refactoring
    debugPrint('Show restore dialog');
  }

  Future<void> _showServerSettings(BuildContext context) async {
    // Note: Server settings kept as-is for now
    // TODO: Move to a dedicated SettingsCubit in future refactoring
    debugPrint('Show server settings');
  }
}
