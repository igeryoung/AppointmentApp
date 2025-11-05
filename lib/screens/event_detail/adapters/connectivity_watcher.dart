import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Wrapper for connectivity_plus that provides a simple Stream<bool isOnline>
class ConnectivityWatcher {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _subscription;
  final _controller = StreamController<bool>.broadcast();

  /// Stream of connectivity status (true = online, false = offline)
  Stream<bool> get onConnectivityChanged => _controller.stream;

  /// Start watching connectivity changes
  void startWatching() {
    debugPrint('🌐 ConnectivityWatcher: Starting connectivity monitoring...');

    _subscription = _connectivity.onConnectivityChanged.listen(
      (ConnectivityResult result) {
        final hasConnection = result != ConnectivityResult.none;
        debugPrint('🌐 ConnectivityWatcher: Connectivity changed - hasConnection: $hasConnection, result: $result');
        _controller.add(hasConnection);
      },
    );

    // Also check initial connectivity state
    _connectivity.checkConnectivity().then((result) {
      final hasConnection = result != ConnectivityResult.none;
      _controller.add(hasConnection);
    });
  }

  /// Stop watching connectivity changes
  void stopWatching() {
    debugPrint('🌐 ConnectivityWatcher: Stopping connectivity monitoring...');
    _subscription?.cancel();
    _subscription = null;
  }

  /// Dispose resources
  void dispose() {
    stopWatching();
    _controller.close();
  }
}
