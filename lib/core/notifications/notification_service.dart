import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notification_intent.dart';
import 'unsupported_notification_service.dart';
import 'windows_notification_service.dart';

export 'unsupported_notification_service.dart';

/// What to put on a single toast.
class NotificationRequest {
  const NotificationRequest({
    required this.id,
    required this.title,
    required this.body,
    this.payload = NotificationIntent.openApp,
    this.actions = const [],
    this.subtitle,
  });

  /// Stable id so a repeat replaces rather than stacks.
  final int id;
  final String title;
  final String body;

  /// Returned when the toast body is tapped. Encodes a [NotificationIntent].
  final String payload;

  /// Buttons. Each button carries its own complete payload (see
  /// [NotificationIntent] for why).
  final List<NotificationAction> actions;

  final String? subtitle;
}

/// Platform-facing notification boundary.
///
/// Hides the differences between platforms — Android gets exact alarms,
/// channels and real action buttons, while Windows can only *show* toasts from
/// an in-process process. Nothing above this layer may touch
/// `package:flutter_local_notifications` directly.
abstract class NotificationService {
  /// Whether this platform has a real implementation. Android arrives in
  /// Phase 2b; until then the UI should say so rather than show dead toggles.
  bool get isSupported;

  /// Prepares the platform. [onResponse] receives the payload string whenever
  /// the user taps the toast or one of its buttons.
  Future<bool> init({required void Function(String payload) onResponse});

  Future<void> show(NotificationRequest request);

  /// Best effort: on unpackaged Windows this is a no-op, which is why
  /// de-duplication never depends on it.
  Future<void> cancelAll();

  Future<void> dispose();
}

/// Notification services are process-wide singletons; one instance, disposed
/// with the app.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = createNotificationService();
  ref.onDispose(service.dispose);
  return service;
});

NotificationService createNotificationService() {
  if (Platform.isWindows) return WindowsNotificationService();
  // Android arrives in Phase 2b (zonedSchedule + exact alarms + boot
  // re-schedule). Until then it falls through to the no-op service so the app
  // still builds and runs everywhere.
  return const UnsupportedNotificationService();
}
