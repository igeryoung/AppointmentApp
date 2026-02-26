import 'dart:async';

/// Background sync failure event emitted after local save succeeded.
class SaveSyncFailure {
  final String bookUuid;
  final String? eventId;
  final String errorMessage;
  final DateTime occurredAt;

  const SaveSyncFailure({
    required this.bookUuid,
    required this.eventId,
    required this.errorMessage,
    required this.occurredAt,
  });
}

/// Global notifier used to surface async save sync failures across screens.
class SaveSyncNotifier {
  SaveSyncNotifier._();

  static final SaveSyncNotifier instance = SaveSyncNotifier._();

  final StreamController<SaveSyncFailure> _failureController =
      StreamController<SaveSyncFailure>.broadcast();

  Stream<SaveSyncFailure> get failures => _failureController.stream;

  void notifyFailure(SaveSyncFailure failure) {
    if (_failureController.isClosed) {
      return;
    }
    _failureController.add(failure);
  }
}
