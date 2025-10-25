import 'dart:io';

/// Environment variable provider - can be overridden for testing or .env files
Map<String, String>? _envOverride;

void setEnvironmentOverride(Map<String, String> env) {
  _envOverride = env;
}

String? _getEnvValue(String key) {
  return _envOverride?[key] ?? Platform.environment[key];
}

/// Database configuration for PostgreSQL connection
class DatabaseConfig {
  final String host;
  final int port;
  final String database;
  final String username;
  final String password;
  final int maxConnections;

  const DatabaseConfig({
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.password,
    this.maxConnections = 10,
  });

  /// Development configuration
  factory DatabaseConfig.development() {
    return DatabaseConfig(
      host: _getEnv('DB_HOST', 'localhost'),
      port: int.parse(_getEnv('DB_PORT', '5433')),
      database: _getEnv('DB_NAME', 'schedule_note_dev'),
      username: _getEnv('DB_USER', 'postgres'),
      password: _requireEnv('DB_PASSWORD'),
      maxConnections: int.parse(_getEnv('DB_MAX_CONNECTIONS', '5')),
    );
  }

  /// Production configuration (read from environment variables)
  factory DatabaseConfig.production() {
    return DatabaseConfig(
      host: _getEnv('DB_HOST', 'localhost'),
      port: int.parse(_getEnv('DB_PORT', '5432')),
      database: _getEnv('DB_NAME', 'schedule_note'),
      username: _getEnv('DB_USER', 'postgres'),
      password: _requireEnv('DB_PASSWORD'),
      maxConnections: int.parse(_getEnv('DB_MAX_CONNECTIONS', '10')),
    );
  }

  static String _getEnv(String key, String defaultValue) {
    return _getEnvValue(key) ?? defaultValue;
  }

  /// Get required environment variable - throws if not set
  static String _requireEnv(String key) {
    final value = _getEnvValue(key);
    if (value == null || value.isEmpty) {
      throw Exception('Required environment variable $key is not set');
    }
    return value;
  }

  @override
  String toString() {
    return 'DatabaseConfig(host: $host, port: $port, database: $database, user: $username)';
  }
}

/// Server configuration
class ServerConfig {
  final String host;
  final int port;
  final bool isDevelopment;
  final bool enableSSL;
  final String? certPath;
  final String? keyPath;

  const ServerConfig({
    required this.host,
    required this.port,
    this.isDevelopment = true,
    this.enableSSL = false,
    this.certPath,
    this.keyPath,
  });

  factory ServerConfig.development() {
    // Development: SSL is optional, defaults to enabled with self-signed certs
    final enableSSL = _getEnvValue('ENABLE_SSL') != 'false'; // Default: true
    return ServerConfig(
      host: _getEnvValue('SERVER_HOST') ?? '0.0.0.0', // Bind to all interfaces for physical device access
      port: int.parse(_getEnvValue('SERVER_PORT') ?? (enableSSL ? '8443' : '8080')),
      isDevelopment: true,
      enableSSL: enableSSL,
      certPath: _getEnvValue('SSL_CERT_PATH') ?? 'certs/cert.pem',
      keyPath: _getEnvValue('SSL_KEY_PATH') ?? 'certs/key.pem',
    );
  }

  factory ServerConfig.production() {
    // Production: SSL is REQUIRED
    final enableSSL = _getEnvValue('ENABLE_SSL') != 'false'; // Default: true
    return ServerConfig(
      host: _getEnvValue('SERVER_HOST') ?? '0.0.0.0',
      port: int.parse(_getEnvValue('SERVER_PORT') ?? '443'),
      isDevelopment: false,
      enableSSL: enableSSL,
      certPath: _getEnvValue('SSL_CERT_PATH'),
      keyPath: _getEnvValue('SSL_KEY_PATH'),
    );
  }

  @override
  String toString() {
    return 'ServerConfig(host: $host, port: $port, isDevelopment: $isDevelopment, SSL: $enableSSL)';
  }
}
