import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'android_notification_service.dart';
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
  /// Subclasses extend rather than implement, so the scheduling defaults above
  /// are inherited — only a platform that genuinely schedules overrides them.
  const NotificationService();

  /// Whether this platform has a real implementation. Android arrives in
  /// Phase 2b; until then the UI should say so rather than show dead toggles.
  bool get isSupported;

  /// Whether this platform can deliver at a future instant without the process
  /// being alive.
  ///
  /// Android schedules through `AlarmManager`, so reminders survive the app
  /// being closed or the device rebooting. Windows has no scheduling API, so
  /// this stays false and the caller's in-process timer drives delivery.
  bool get supportsScheduling => false;

  /// Prepares the platform. [onResponse] receives the payload string whenever
  /// the user taps the toast or one of its buttons.
  Future<bool> init({required void Function(String payload) onResponse});

  Future<void> show(NotificationRequest request);

  /// Hands [request] to the OS to be shown at [when].
  ///
  /// Returns true only when the platform has genuinely taken responsibility
  /// for this occurrence — the caller records it as delivered on that
  /// condition alone, so a false here must mean nothing was scheduled and the
  /// in-process fallback should still fire.
  ///
  /// Platforms that cannot schedule return false and show nothing.
  Future<bool> schedule(NotificationRequest request, DateTime when) =>
      Future<bool>.value(false);

  /// Cancels any notification still pending for [id].
  Future<void> cancel(int id) async {}

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
  if (Platform.isAndroid) return AndroidNotificationService();
  return const UnsupportedNotificationService();
}
