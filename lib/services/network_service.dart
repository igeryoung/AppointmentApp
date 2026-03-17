import 'package:connectivity_plus/connectivity_plus.dart';

/// Service for checking network connectivity
/// Enforces network requirement for sync operations
class NetworkService {
  final Connectivity _connectivity = Connectivity();

  /// Check if device has internet connectivity
  /// Returns true if connected to WiFi, mobile, or ethernet
  Future<bool> hasConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return _hasConnection(results);
    } catch (e) {
      return false;
    }
  }

  /// Require network connectivity, throw exception if offline
  /// Use this before performing sync operations
  Future<void> requireConnectivity() async {
    final hasConnection = await hasConnectivity();
    if (!hasConnection) {
      throw NetworkException('Network connection required for this operation');
    }
  }

  /// Stream of connectivity changes
  /// Subscribe to this to react to network changes
  Stream<List<ConnectivityResult>> get onConnectivityChanged {
    return _connectivity.onConnectivityChanged;
  }

  /// Check if currently connected to WiFi
  Future<bool> isConnectedToWiFi() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return results.contains(ConnectivityResult.wifi);
    } catch (e) {
      return false;
    }
  }

  /// Check if currently connected to mobile data
  Future<bool> isConnectedToMobile() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return results.contains(ConnectivityResult.mobile);
    } catch (e) {
      return false;
    }
  }

  bool _hasConnection(List<ConnectivityResult> results) {
    return results.any((result) {
      return result == ConnectivityResult.wifi ||
          result == ConnectivityResult.mobile ||
          result == ConnectivityResult.ethernet;
    });
  }
}

/// Exception thrown when network is required but unavailable
class NetworkException implements Exception {
  final String message;

  NetworkException(this.message);

  @override
  String toString() => 'NetworkException: $message';
}
