import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Wrapper for connectivity_plus that provides a simple Stream<bool isOnline>

class ConnectivityWatcher {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  final _controller = StreamController<bool>.broadcast();

  /// Stream of connectivity status (true = online, false = offline)
  Stream<bool> get onConnectivityChanged => _controller.stream;

  /// Start watching connectivity changes
  void startWatching() {
    _subscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        _controller.add(_hasConnection(results));
      },
    );

    // Also check initial connectivity state
    _connectivity.checkConnectivity().then((results) {
      _controller.add(_hasConnection(results));
    });
  }

  bool _hasConnection(List<ConnectivityResult> results) {
    return results.any((result) => result != ConnectivityResult.none);
  }

  /// Stop watching connectivity changes
  void stopWatching() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// Dispose resources
  void dispose() {
    stopWatching();
    _controller.close();
  }
}
