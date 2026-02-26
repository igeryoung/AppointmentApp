import 'package:supabase/supabase.dart';

import '../config/database_config.dart';

/// Database connection manager backed by Supabase SDK.
///
/// New code should use [client] directly with table/query-builder operations.
class DatabaseConnection {
  static DatabaseConnection? _instance;
  final DatabaseConfig config;
  late final SupabaseClient _client;

  DatabaseConnection._internal(this.config) {
    if (!config.useSupabaseSdk) {
      throw Exception(
        'Supabase SDK mode requires SUPABASE_URL and SUPABASE_KEY in .env',
      );
    }
    _client = SupabaseClient(config.supabaseUrl!, config.supabaseKey!);
  }

  factory DatabaseConnection({DatabaseConfig? config}) {
    _instance ??= DatabaseConnection._internal(
      config ?? DatabaseConfig.development(),
    );
    return _instance!;
  }

  SupabaseClient get client => _client;

  /// Legacy SQL interfaces are intentionally disabled.
  Future<void> query(String sql, {Map<String, dynamic>? parameters}) async {
    throw UnsupportedError(
      'Raw SQL path disabled. Migrate this call to Supabase query builder. SQL: $sql',
    );
  }

  /// Legacy SQL interfaces are intentionally disabled.
  Future<List<Map<String, dynamic>>> queryRows(
    String sql, {
    Map<String, dynamic>? parameters,
  }) async {
    throw UnsupportedError(
      'Raw SQL path disabled. Migrate this call to Supabase query builder. SQL: $sql',
    );
  }

  /// Legacy SQL interfaces are intentionally disabled.
  Future<Map<String, dynamic>?> querySingle(
    String sql, {
    Map<String, dynamic>? parameters,
  }) async {
    throw UnsupportedError(
      'Raw SQL path disabled. Migrate this call to Supabase query builder. SQL: $sql',
    );
  }

  /// No-op compatibility wrapper.
  Future<T> transaction<T>(Future<T> Function() callback) async {
    return callback();
  }

  Future<void> close() async {}

  /// Health check using a minimal table query.
  Future<bool> healthCheck() async {
    try {
      await _client.from('devices').select('id').limit(1);
      return true;
    } catch (e) {
      print('❌ Database health check failed: $e');
      return false;
    }
  }

  Future<void> runMigrations(String migrationSql) async {
    final _ = migrationSql;
    throw UnsupportedError(
      'Server-side migrations via raw SQL are disabled in SDK-only mode. '
      'Run SQL in Supabase SQL editor instead.',
    );
  }

  static void resetInstance() {
    _instance = null;
  }
}
