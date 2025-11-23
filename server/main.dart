import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:dotenv/dotenv.dart';
import 'lib/config/database_config.dart';
import 'lib/database/connection.dart';
import 'lib/routes/device_routes.dart';
import 'lib/routes/sync_routes.dart';
import 'lib/routes/book_backup_routes.dart';
import 'lib/routes/note_routes.dart';
import 'lib/routes/drawing_routes.dart';
import 'lib/routes/batch_routes.dart';
import 'lib/routes/dashboard_routes.dart';

void main(List<String> args) async {
  // Load environment variables from .env file
  final env = DotEnv();
  final envFile = File('../.env');
  if (await envFile.exists()) {
    env.load(['../.env']);
    // Merge with Platform.environment
    final mergedEnv = Map<String, String>.from(Platform.environment);
    mergedEnv.addAll(env.map);
    setEnvironmentOverride(mergedEnv);
    print('📄 Loaded environment variables from .env file');
  }

  // Parse command line arguments
  final isDevelopment = args.contains('--dev') || args.isEmpty;

  // Initialize configuration
  final serverConfig = isDevelopment
      ? ServerConfig.development()
      : ServerConfig.production();
  final dbConfig = isDevelopment
      ? DatabaseConfig.development()
      : DatabaseConfig.production();

  print('🚀 Starting Schedule Note Sync Server');
  print('   Mode: ${isDevelopment ? 'Development' : 'Production'}');
  print('   $serverConfig');
  print('   $dbConfig');

  // Initialize database connection
  final db = DatabaseConnection(config: dbConfig);

  // Health check
  print('🔍 Checking database connection...');
  final isHealthy = await db.healthCheck();
  if (!isHealthy) {
    print('❌ Database connection failed. Please check your configuration.');
    exit(1);
  }
  print('✅ Database connection established');

  // Run migrations if needed
  if (args.contains('--migrate')) {
    print('🔄 Running migrations...');
    final migrations = [
      'migrations/001_initial_schema.sql',
      'migrations/002_book_backups.sql',
      'migrations/003_add_book_uuid.sql',
    ];

    for (final migrationPath in migrations) {
      final migrationFile = File(migrationPath);
      if (await migrationFile.exists()) {
        print('   Running: ${migrationPath.split('/').last}');
        final migrationSql = await migrationFile.readAsString();
        await db.runMigrations(migrationSql);
      } else {
        print('   ⚠️  Migration file not found: $migrationPath');
      }
    }
    print('✅ Migrations completed');
  }

  // Create router and add routes
  final app = Router();

  // Device routes
  final deviceRoutes = DeviceRoutes(db);
  app.mount('/api/devices/', deviceRoutes.router);

  // Sync routes
  final syncRoutes = SyncRoutes(db);
  app.mount('/api/sync/', syncRoutes.router);

  // Book backup routes
  final backupDir = Platform.environment['BACKUP_DIR'] ?? 'server/backups';
  final bookBackupRoutes = BookBackupRoutes(db, backupDir: backupDir);

  // File-based backup API
  app.mount('/api/books/', bookBackupRoutes.bookScopedRouter);
  app.mount('/api/backups/', bookBackupRoutes.backupScopedRouter);

  // JSON-based backup API
  app.mount('/api/books/', bookBackupRoutes.jsonBasedRouter);

  // Book creation API
  app.mount('/api/create-books', bookBackupRoutes.createBookRouter);

  // Note routes (Server-Store API)
  final noteRoutes = NoteRoutes(db);
  app.mount('/api/notes/', noteRoutes.router);
  app.mount('/api/books/', noteRoutes.bookScopedRouter);

  // Drawing routes (Server-Store API)
  final drawingRoutes = DrawingRoutes(db);
  app.mount('/api/drawings/', drawingRoutes.router);
  app.mount('/api/books/', drawingRoutes.bookScopedRouter);

  // Batch routes (Server-Store API - Batch Operations)
  final batchRoutes = BatchRoutes(db);
  app.mount('/api/batch/', batchRoutes.router);

  // Dashboard routes (Monitoring API - Read-only)
  final dashboardUsername = Platform.environment['DASHBOARD_USERNAME'] ?? 'admin';
  final dashboardPassword = Platform.environment['DASHBOARD_PASSWORD'] ?? 'admin123';
  final dashboardRoutes = DashboardRoutes(
    db,
    adminUsername: dashboardUsername,
    adminPassword: dashboardPassword,
  );
  app.mount('/api/dashboard/', dashboardRoutes.router);

  // Health check endpoint
  app.get('/health', (Request request) async {
    final dbHealthy = await db.healthCheck();
    return Response.ok(
      '{"status": "${dbHealthy ? 'healthy' : 'unhealthy'}", "service": "schedule_note_sync_server"}',
      headers: {'Content-Type': 'application/json'},
    );
  });

  // Root endpoint
  app.get('/', (Request request) {
    return Response.ok(
      '{"message": "Schedule Note Sync Server", "version": "1.0.0", "docs": "/docs"}',
      headers: {'Content-Type': 'application/json'},
    );
  });

  // OpenAPI spec
  app.get('/openapi.yaml', (Request request) async {
    final file = File('openapi.yaml');
    final content = await file.readAsString();
    return Response.ok(
      content,
      headers: {'Content-Type': 'text/yaml'},
    );
  });

  // Swagger UI redirect
  app.get('/docs', (Request request) {
    return Response.movedPermanently('/docs/');
  });

  // Serve Swagger UI
  final swaggerHandler = createStaticHandler(
    'public/swagger-ui',
    defaultDocument: 'index.html',
  );
  app.mount('/docs/', swaggerHandler);

  // Add middleware
  // Note: CORS middleware removed - not needed for mobile-only apps (native iOS/Android ignore CORS)
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_errorHandler())
      .addMiddleware(_httpsRedirectMiddleware(serverConfig))
      .addHandler(app);

  // Start server with HTTPS support
  HttpServer server;
  if (serverConfig.enableSSL) {
    // HTTPS mode
    if (serverConfig.certPath == null || serverConfig.keyPath == null) {
      print('❌ ERROR: SSL enabled but certificate paths not configured');
      print('   Set SSL_CERT_PATH and SSL_KEY_PATH environment variables');
      exit(1);
    }

    final context = SecurityContext()
      ..useCertificateChain(serverConfig.certPath!)
      ..usePrivateKey(serverConfig.keyPath!);

    server = await HttpServer.bindSecure(
      serverConfig.host,
      serverConfig.port,
      context,
    );

    print('✅ HTTPS enabled (${serverConfig.isDevelopment ? 'self-signed cert' : 'production cert'})');
  } else {
    // HTTP mode - only allowed in development
    if (!serverConfig.isDevelopment) {
      print('');
      print('❌ FATAL ERROR: Production server cannot start without HTTPS!');
      print('');
      print('   This would violate medical data protection laws (HIPAA, GDPR).');
      print('   Patient data MUST be encrypted in transit.');
      print('');
      print('   To fix:');
      print('   1. Set ENABLE_SSL=true in environment');
      print('   2. Provide SSL_CERT_PATH and SSL_KEY_PATH');
      print('   3. Use Let\'s Encrypt for free SSL certificates');
      print('');
      print('   See: doc/security/P0_CRITICAL/02_https_enforcement.md');
      print('');
      exit(1);
    }

    server = await HttpServer.bind(serverConfig.host, serverConfig.port);
    print('⚠️  HTTP mode (DEVELOPMENT ONLY - insecure)');
  }

  shelf_io.serveRequests(server, handler);

  final protocol = serverConfig.enableSSL ? 'https' : 'http';
  print('✅ Server listening on $protocol://${server.address.host}:${server.port}');
  print('');
  print('📚 API Documentation:');
  print('   $protocol://${server.address.host}:${server.port}/docs');
  print('');
  print('📌 Endpoints:');
  print('   GET  /health - Health check');
  print('   POST /api/devices/register - Register device');
  print('   GET  /api/devices/<id> - Get device info');
  print('');
  print('   === Sync API ===');
  print('   POST /api/sync/pull - Pull server changes');
  print('   POST /api/sync/push - Push local changes');
  print('   POST /api/sync/full - Full bidirectional sync');
  print('   POST /api/sync/resolve-conflict - Resolve conflict');
  print('');
  print('   === Book Creation API ===');
  print('   POST /api/create-books - Create new book and get UUID');
  print('');
  print('   === Book Backup API (File-based) ===');
  print('   POST /api/books/<bookId>/backup - Create backup');
  print('   GET  /api/books/<bookId>/backups - List backups for book');
  print('   GET  /api/backups/<backupId>/download - Download backup file');
  print('   POST /api/backups/<backupId>/restore - Restore from backup');
  print('   DELETE /api/backups/<backupId> - Delete backup');
  print('');
  print('   === Book Backup API (Legacy JSON - deprecated) ===');
  print('   POST /api/books/upload - Upload book backup (JSON)');
  print('   GET  /api/books/list - List book backups');
  print('   GET  /api/books/download/<id> - Download backup data');
  print('   POST /api/books/restore/<id> - Restore book from backup');
  print('');
  print('   === Server-Store API (Notes & Drawings) ===');
  print('   GET  /api/books/<bookId>/events/<eventId>/note - Get note');
  print('   POST /api/books/<bookId>/events/<eventId>/note - Create/update note');
  print('   DELETE /api/books/<bookId>/events/<eventId>/note - Delete note');
  print('   POST /api/notes/batch - Batch get notes');
  print('   GET  /api/books/<bookId>/drawings?date=X&viewMode=Y - Get drawing');
  print('   POST /api/books/<bookId>/drawings - Create/update drawing');
  print('   DELETE /api/books/<bookId>/drawings?date=X&viewMode=Y - Delete drawing');
  print('   POST /api/drawings/batch - Batch get drawings');
  print('');
  print('   === Batch Operations API ===');
  print('   POST /api/batch/save - Batch save notes + drawings (atomic)');
  print('');
  print('   === Dashboard API (Monitoring) ===');
  print('   POST /api/dashboard/auth/login - Admin login');
  print('   GET  /api/dashboard/stats - Dashboard statistics');
  print('   Dashboard credentials: $dashboardUsername / $dashboardPassword');
  print('');

  // Graceful shutdown
  ProcessSignal.sigint.watch().listen((_) async {
    print('\n🛑 Shutting down server...');
    await server.close(force: true);
    await db.close();
    print('✅ Server stopped');
    exit(0);
  });
}

/// HTTPS redirect middleware
Middleware _httpsRedirectMiddleware(ServerConfig config) {
  return (Handler handler) {
    return (Request request) async {
      // Skip redirect for health checks and docs
      if (request.url.path.startsWith('health') ||
          request.url.path.startsWith('docs')) {
        return handler(request);
      }

      // If SSL is enabled but request is HTTP, this shouldn't happen
      // since we're binding to HTTPS, but just in case
      return handler(request);
    };
  };
}

/// Error handling middleware
Middleware _errorHandler() {
  return (Handler handler) {
    return (Request request) async {
      try {
        return await handler(request);
      } catch (error, stackTrace) {
        print('❌ Unhandled error: $error');
        print('   Stack trace: $stackTrace');

        return Response.internalServerError(
          body: '{"success": false, "message": "Internal server error"}',
          headers: {'Content-Type': 'application/json'},
        );
      }
    };
  };
}
