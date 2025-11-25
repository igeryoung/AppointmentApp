import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Service for checking network connectivity
/// Enforces network requirement for sync operations
class NetworkService {
  final Connectivity _connectivity = Connectivity();

  /// Check if device has internet connectivity
  /// Returns true if connected to WiFi, mobile, or ethernet
  Future<bool> hasConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();

      // Check if any connection type is available
      if (result.contains(ConnectivityResult.none)) {
        debugPrint('📡 No network connectivity');
        return false;
      }

      // Has wifi, mobile, or ethernet connection
      final hasConnection = result.contains(ConnectivityResult.wifi) ||
          result.contains(ConnectivityResult.mobile) ||
          result.contains(ConnectivityResult.ethernet);

      if (hasConnection) {
        debugPrint('📡 Network connectivity: $result');
      } else {
        debugPrint('📡 No active network connection');
      }

      return hasConnection;
    } catch (e) {
      debugPrint('❌ Failed to check connectivity: $e');
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
      final result = await _connectivity.checkConnectivity();
      return result.contains(ConnectivityResult.wifi);
    } catch (e) {
      debugPrint('❌ Failed to check WiFi connectivity: $e');
      return false;
    }
  }

  /// Check if currently connected to mobile data
  Future<bool> isConnectedToMobile() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result.contains(ConnectivityResult.mobile);
    } catch (e) {
      debugPrint('❌ Failed to check mobile connectivity: $e');
      return false;
    }
  }
}

/// Exception thrown when network is required but unavailable
class NetworkException implements Exception {
  final String message;

  NetworkException(this.message);

  @override
  String toString() => 'NetworkException: $message';
}
