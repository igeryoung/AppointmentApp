import 'package:postgres/postgres.dart';
import '../config/database_config.dart';

/// PostgreSQL connection pool manager
class DatabaseConnection {
  static DatabaseConnection? _instance;
  late final Pool _pool;
  final DatabaseConfig config;

  DatabaseConnection._internal(this.config) {
    _pool = Pool.withEndpoints(
      [
        Endpoint(
          host: config.host,
          port: config.port,
          database: config.database,
          username: config.username,
          password: config.password,
        ),
      ],
      settings: PoolSettings(
        maxConnectionCount: config.maxConnections,
        maxConnectionAge: const Duration(hours: 1),
        sslMode: SslMode.disable, // Enable in production
      ),
    );
  }

  /// Get singleton instance
  factory DatabaseConnection({DatabaseConfig? config}) {
    _instance ??= DatabaseConnection._internal(
      config ?? DatabaseConfig.development(),
    );
    return _instance!;
  }

  /// Get connection pool
  Pool get pool => _pool;

  /// Execute a query with parameters
  Future<Result> query(
    String sql, {
    Map<String, dynamic>? parameters,
  }) async {
    try {
      return await _pool.execute(
        Sql.named(sql),
        parameters: parameters,
      );
    } catch (e) {
      print('❌ Database query error: $e');
      print('   SQL: $sql');
      print('   Parameters: $parameters');
      rethrow;
    }
  }

  /// Execute a query and return rows
  Future<List<Map<String, dynamic>>> queryRows(
    String sql, {
    Map<String, dynamic>? parameters,
  }) async {
    final result = await query(sql, parameters: parameters);
    return result.map((row) => row.toColumnMap()).toList();
  }

  /// Execute a query and return single row or null
  Future<Map<String, dynamic>?> querySingle(
    String sql, {
    Map<String, dynamic>? parameters,
  }) async {
    final result = await query(sql, parameters: parameters);
    if (result.isEmpty) return null;
    return result.first.toColumnMap();
  }

  /// Execute within a transaction
  Future<T> transaction<T>(
    Future<T> Function(Session) callback,
  ) async {
    return await _pool.withConnection((connection) async {
      return await connection.runTx((session) async {
        return await callback(session);
      });
    });
  }

  /// Close the connection pool
  Future<void> close() async {
    await _pool.close();
  }

  /// Health check - verify database connectivity
  Future<bool> healthCheck() async {
    try {
      final result = await querySingle('SELECT 1 as health');
      return result != null && result['health'] == 1;
    } catch (e) {
      print('❌ Database health check failed: $e');
      return false;
    }
  }

  /// Run migrations from SQL file
  Future<void> runMigrations(String migrationSql) async {
    try {
      print('🔄 Running database migrations...');
      final statements = migrationSql.split(';').where((s) => s.trim().isNotEmpty);

      for (final statement in statements) {
        await query(statement.trim());
      }

      print('✅ Migrations completed successfully');
    } catch (e) {
      print('❌ Migration failed: $e');
      rethrow;
    }
  }

  /// Reset instance (for testing)
  static void resetInstance() {
    _instance = null;
  }
}
