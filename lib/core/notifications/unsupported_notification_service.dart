import 'notification_service.dart';

/// Fallback used on platforms without an implementation (and on Android until
/// Phase 2b). Reports itself as unavailable so the UI can say so honestly
/// rather than pretending alerts are on.
class UnsupportedNotificationService implements NotificationService {
  const UnsupportedNotificationService();

  @override
  bool get isSupported => false;

  @override
  Future<bool> init({required void Function(String payload) onResponse}) async =>
      false;

  @override
  Future<void> show(NotificationRequest request) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> dispose() async {}
}
