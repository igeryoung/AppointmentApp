import 'package:get_it/get_it.dart';
import 'database_service_interface.dart';
import 'database/prd_database_service.dart';
import 'time_service.dart';
import 'api_client.dart';
import 'server_config_service.dart';
import '../repositories/book_repository.dart';
import '../repositories/book_repository_impl.dart';
import '../repositories/event_repository.dart';
import '../repositories/event_repository_impl.dart';
import '../repositories/note_repository.dart';
import '../repositories/note_repository_impl.dart';
import '../repositories/drawing_repository.dart';
import '../repositories/drawing_repository_impl.dart';
import '../repositories/device_repository.dart';
import '../repositories/device_repository_impl.dart';
import 'note_content_service.dart';
import 'drawing_content_service.dart';
import 'book_order_service.dart';
import '../cubits/book_list_cubit.dart';
import '../cubits/schedule_cubit.dart';
import '../cubits/event_detail_cubit.dart';

final getIt = GetIt.instance;

/// Sets up all service dependencies for dependency injection
/// Call this once during app initialization
Future<void> setupServices() async {
  // Database Service - Register as singleton since database should only be initialized once
  getIt.registerSingleton<IDatabaseService>(PRDDatabaseService());

  // Time Service - Singleton (uses its own singleton instance)
  getIt.registerSingleton<TimeService>(TimeService.instance);

  // Server Config Service - Lazy singleton
  getIt.registerLazySingleton<ServerConfigService>(
    () => ServerConfigService(getIt<IDatabaseService>() as PRDDatabaseService),
  );

  // Repositories - Lazy singletons
  final db = getIt<IDatabaseService>();
  if (db is PRDDatabaseService) {
    // Note: BookRepository will be re-registered with ApiClient after server config loads
    // For now, register without ApiClient (book creation will fail until API is configured)
    getIt.registerLazySingleton<IBookRepository>(
      () => BookRepositoryImpl(
        () => db.database,
        apiClient: null, // Will be updated after server config loads
        dbService: db,
      ),
    );

    getIt.registerLazySingleton<IEventRepository>(
      () => EventRepositoryImpl(
        () => db.database,
        (eventId) => db.getCachedNote(eventId),
      ),
    );

    getIt.registerLazySingleton<INoteRepository>(
      () => NoteRepositoryImpl(() => db.database),
    );

    getIt.registerLazySingleton<IDrawingRepository>(
      () => DrawingRepositoryImpl(() => db.database),
    );

    getIt.registerLazySingleton<IDeviceRepository>(
      () => DeviceRepositoryImpl(() => db.database),
    );
  }

  // Note: ApiClient, CacheManager, and ContentService are initialized
  // dynamically in screens after server configuration is loaded.
  // For now, we register the new content services once API client is available.

  // Phase 3 Services - Lazy singletons
  // Note: These require ApiClient which is initialized after server config
  // For now, we'll defer registration until ApiClient is available
  // TODO: Refactor to make ApiClient available during setupServices

  // Book Order Service - Lazy singleton
  getIt.registerLazySingleton<BookOrderService>(() => BookOrderService());

  // Phase 4 Cubits - Factories (each screen gets fresh instance)
  // BookListCubit
  getIt.registerFactory<BookListCubit>(
    () => BookListCubit(
      getIt<IBookRepository>(),
      getIt<BookOrderService>(),
    ),
  );

  // Get server URL from config (or use default)
  final serverConfig = getIt<ServerConfigService>();
  final serverUrl = await serverConfig.getServerUrl() ?? 'http://localhost:8080';

  // Create ApiClient
  final apiClient = ApiClient(baseUrl: serverUrl);

  // Register content services immediately
  await registerContentServices(apiClient);
}

/// Register content services after ApiClient is initialized
/// Call this after server configuration is loaded
Future<void> registerContentServices(ApiClient apiClient) async {
  {
    // Re-register BookRepository with ApiClient
    final db = getIt<IDatabaseService>();
    if (db is PRDDatabaseService) {
      if (getIt.isRegistered<IBookRepository>()) {
        getIt.unregister<IBookRepository>();
      }
      getIt.registerLazySingleton<IBookRepository>(
        () => BookRepositoryImpl(
          () => db.database,
          apiClient: apiClient,
          dbService: db,
        ),
      );
    }

    // Register Phase 3 content services
    if (getIt.isRegistered<NoteContentService>()) {
      getIt.unregister<NoteContentService>();
    }
    getIt.registerLazySingleton<NoteContentService>(
      () => NoteContentService(
        apiClient,
        getIt<INoteRepository>(),
        getIt<IEventRepository>(),
        getIt<IDeviceRepository>(),
      ),
    );

    if (getIt.isRegistered<DrawingContentService>()) {
      getIt.unregister<DrawingContentService>();
    }
    getIt.registerLazySingleton<DrawingContentService>(
      () => DrawingContentService(
        apiClient,
        getIt<IDrawingRepository>(),
        getIt<IDeviceRepository>(),
      ),
    );

    // Register Phase 4 cubits that depend on content services
    if (getIt.isRegistered<ScheduleCubit>()) {
      getIt.unregister<ScheduleCubit>();
    }
    getIt.registerFactory<ScheduleCubit>(
      () => ScheduleCubit(
        getIt<IEventRepository>(),
        getIt<DrawingContentService>(),
        getIt<TimeService>(),
        apiClient: apiClient,
        deviceRepository: getIt<IDeviceRepository>(),
      ),
    );

    if (getIt.isRegistered<EventDetailCubit>()) {
      getIt.unregister<EventDetailCubit>();
    }
    getIt.registerFactory<EventDetailCubit>(
      () => EventDetailCubit(
        getIt<IEventRepository>(),
        getIt<NoteContentService>(),
      ),
    );
  }
}

/// Resets all registered services - useful for testing
void resetServices() {
  getIt.reset();
}
