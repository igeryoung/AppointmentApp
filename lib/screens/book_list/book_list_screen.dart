import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import '../../cubits/schedule_cubit.dart';
import '../../l10n/app_localizations.dart';
import '../../models/book.dart';
import '../../services/service_locator.dart';
import '../schedule_screen.dart';
import 'book_list_controller.dart';
import 'adapters/adapters.dart';
import 'utils/platform_utils.dart';
import 'widgets/book_list_view.dart';

/// Book List Screen - Thin View layer
/// Only responsible for UI assembly and routing
class BookListScreen extends StatefulWidget {
  const BookListScreen({super.key});

  @override
  State<BookListScreen> createState() => _BookListScreenState();
}

class _BookListScreenState extends State<BookListScreen> {
  late final BookListController _controller;

  @override
  void initState() {
    super.initState();
    _controller = BookListController(
      repo: BookRepository.fromGetIt(),
      order: BookOrderAdapter.fromGetIt(),
      serverConfig: ServerConfigAdapter.fromGetIt(),
      deviceReg: DeviceRegistrationAdapter.fromGetIt(),
    )..initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _controller,
      child: Consumer<BookListController>(
        builder: (context, controller, _) {
          final state = controller.state;

          return Scaffold(
            appBar: _buildAppBar(context, controller),
            body: state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      if (state.errorMessage != null)
                        MaterialBanner(
                          content: Text(state.errorMessage!),
                          backgroundColor: Colors.red.shade50,
                          actions: [
                            TextButton(
                              onPressed: controller.clearError,
                              child: const Text('Dismiss'),
                            ),
                          ],
                        ),
                      Expanded(
                        child: BookListView(
                          books: state.books,
                          onRefresh: controller.reload,
                          onReorder: controller.reorderBooks,
                          onTap: _openSchedule,
                          onRename: (book) =>
                              controller.promptRename(context, book),
                          onArchive: (book) =>
                              controller.promptArchive(context, book),
                          onDelete: (book) =>
                              controller.promptDelete(context, book),
                        ),
                      ),
                    ],
                  ),
            floatingActionButton: FloatingActionButton(
              onPressed: () => controller.promptCreate(context),
              tooltip: AppLocalizations.of(context)!.createNewBook,
              child: const Icon(Icons.add),
            ),
          );
        },
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context, BookListController controller) {
    final l10n = AppLocalizations.of(context)!;

    return AppBar(
      title: Text(l10n.appointmentBooks),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: controller.reload,
        ),
        // Import from Server
        if (!PlatformUtils.isWeb)
          IconButton(
            icon: const Icon(Icons.cloud_download),
            tooltip: 'Import from Server',
            onPressed: () => controller.openImportFromServerFlow(context),
          ),
        // Server Settings
        if (!PlatformUtils.isWeb)
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Server Settings',
            onPressed: () => controller.openServerSettingsFlow(context),
          ),
      ],
    );
  }

  /// Open schedule screen for a book
  void _openSchedule(Book book) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BlocProvider(
          create: (context) => getIt<ScheduleCubit>()..initialize(book.uuid),
          child: ScheduleScreen(book: book),
        ),
      ),
    );
  }
}
