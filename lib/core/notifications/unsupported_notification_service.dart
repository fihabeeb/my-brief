import 'notification_service.dart';

/// Fallback used on platforms without an implementation. Reports itself as
/// unavailable so the UI can say so honestly rather than pretending alerts
/// are on.
class UnsupportedNotificationService extends NotificationService {
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
