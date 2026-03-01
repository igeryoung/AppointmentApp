import 'dart:io';

/// Environment variable provider - can be overridden for testing or .env files
Map<String, String>? _envOverride;

void setEnvironmentOverride(Map<String, String> env) {
  _envOverride = env;
}

String? _getEnvValue(String key) {
  return _envOverride?[key] ?? Platform.environment[key];
}

bool _isTruthy(String? value) {
  if (value == null) return false;
  switch (value.trim().toLowerCase()) {
    case '1':
    case 'true':
    case 'yes':
    case 'on':
      return true;
    default:
      return false;
  }
}

bool _isRunningBehindManagedTlsProxy() {
  return (_getEnvValue('RAILWAY_ENVIRONMENT') ?? '').trim().isNotEmpty ||
      (_getEnvValue('RAILWAY_PROJECT_ID') ?? '').trim().isNotEmpty;
}

/// Supabase-only database configuration.
class DatabaseConfig {
  final String? supabaseUrl;
  final String? supabaseKey;
  final int maxConnections;

  const DatabaseConfig({
    required this.supabaseUrl,
    required this.supabaseKey,
    this.maxConnections = 10,
  });

  bool get useSupabaseSdk =>
      (supabaseUrl ?? '').trim().isNotEmpty &&
      (supabaseKey ?? '').trim().isNotEmpty;

  /// Development configuration (same as production in SDK-only mode).
  factory DatabaseConfig.development() {
    return _fromEnvironment();
  }

  /// Production configuration (same as development in SDK-only mode).
  factory DatabaseConfig.production() {
    return _fromEnvironment();
  }

  static DatabaseConfig _fromEnvironment() {
    final supabaseUrl = _requireEnv('SUPABASE_URL');
    final supabaseKey = _requireEnv('SUPABASE_KEY');

    if (supabaseKey.trim().startsWith('sb_publishable_')) {
      throw Exception(
        'SUPABASE_KEY is a publishable key. '
        'Backend must use service_role/secret key.',
      );
    }

    final uri = Uri.tryParse(supabaseUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.trim().isEmpty) {
      throw Exception(
        'SUPABASE_URL must be a valid https URL, e.g. '
        'https://<project-ref>.supabase.co',
      );
    }

    final maxConnections = int.tryParse(
      (_getEnvValue('SUPABASE_MAX_CONNECTIONS') ?? '').trim(),
    );

    return DatabaseConfig(
      supabaseUrl: supabaseUrl,
      supabaseKey: supabaseKey,
      maxConnections: (maxConnections == null || maxConnections <= 0)
          ? 10
          : maxConnections,
    );
  }

  static String _requireEnv(String key) {
    final value = _getEnvValue(key)?.trim();
    if (value == null || value.isEmpty) {
      throw Exception('Required environment variable $key is not set');
    }
    return value;
  }

  @override
  String toString() {
    final url = supabaseUrl ?? '<unset>';
    return 'DatabaseConfig(mode: supabase-sdk, url: $url)';
  }
}

/// Server configuration
class ServerConfig {
  final String host;
  final int port;
  final bool isDevelopment;
  final bool enableSSL;
  final bool managedTlsTerminated;
  final String? certPath;
  final String? keyPath;

  const ServerConfig({
    required this.host,
    required this.port,
    this.isDevelopment = true,
    this.enableSSL = false,
    this.managedTlsTerminated = false,
    this.certPath,
    this.keyPath,
  });

  factory ServerConfig.development() {
    // Development: SSL is optional, defaults to enabled with self-signed certs
    final enableSSL = _getEnvValue('ENABLE_SSL') != 'false'; // Default: true
    return ServerConfig(
      host:
          _getEnvValue('SERVER_HOST') ??
          '0.0.0.0', // Bind to all interfaces for physical device access
      port: int.parse(
        _getEnvValue('SERVER_PORT') ?? (enableSSL ? '8443' : '8080'),
      ),
      isDevelopment: true,
      enableSSL: enableSSL,
      managedTlsTerminated: false,
      certPath: _getEnvValue('SSL_CERT_PATH') ?? 'certs/cert.pem',
      keyPath: _getEnvValue('SSL_KEY_PATH') ?? 'certs/key.pem',
    );
  }

  factory ServerConfig.production() {
    final runningBehindManagedTlsProxy = _isRunningBehindManagedTlsProxy();
    final enableSSL = _getEnvValue('ENABLE_SSL') == null
        ? !runningBehindManagedTlsProxy
        : _isTruthy(_getEnvValue('ENABLE_SSL'));
    final port = int.tryParse(
      _getEnvValue('PORT') ?? _getEnvValue('SERVER_PORT') ?? '',
    );

    return ServerConfig(
      host: _getEnvValue('SERVER_HOST') ?? '0.0.0.0',
      port: port ?? (enableSSL ? 443 : 8080),
      isDevelopment: false,
      enableSSL: enableSSL,
      managedTlsTerminated: runningBehindManagedTlsProxy && !enableSSL,
      certPath: _getEnvValue('SSL_CERT_PATH'),
      keyPath: _getEnvValue('SSL_KEY_PATH'),
    );
  }

  @override
  String toString() {
    return 'ServerConfig(host: $host, port: $port, isDevelopment: $isDevelopment, SSL: $enableSSL)';
  }
}
