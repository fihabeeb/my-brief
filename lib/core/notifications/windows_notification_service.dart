import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_service.dart';

/// Windows toast implementation.
///
/// Windows can only *show* toasts — it has no scheduling API (hence the
/// in-process [NotificationScheduler]) and `cancel()` is a no-op without MSIX
/// package identity. Action buttons are best-effort: the platform returns the
/// pressed button's `arguments` as both `payload` and `actionId`, so callers
/// must encode a complete intent in every string.
class WindowsNotificationService implements NotificationService {
  /// Identifies this app's toast activation callback. Stable per app; changing
  /// it breaks toast clicks until Windows re-registers the shortcut.
  static const _guid = '544513d2-a6f2-42e4-b3b4-59922cbc92df';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  void Function(String payload)? _onResponse;

  @override
  bool get isSupported => true;

  @override
  Future<bool> init({required void Function(String payload) onResponse}) async {
    // Always refresh the callback: the scheduler is rebuilt whenever a setting
    // changes, and the plugin can only be initialized once.
    _onResponse = onResponse;
    if (_ready) return true;
    const settings = InitializationSettings(
      windows: WindowsInitializationSettings(
        appName: 'My Brief',
        appUserModelId: 'com.fihabeeb.mybrief',
        guid: _guid,
      ),
    );
    final ok = await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) =>
          _onResponse?.call(response.payload ?? ''),
    );
    _ready = ok ?? false;
    return _ready;
  }

  @override
  Future<void> show(NotificationRequest request) async {
    if (!_ready) return;
    await _plugin.show(
      id: request.id,
      title: request.title,
      body: request.body,
      payload: request.payload,
      notificationDetails: NotificationDetails(
        windows: WindowsNotificationDetails(
          subtitle: request.subtitle,
          actions: [
            for (final a in request.actions)
              WindowsAction(content: a.label, arguments: a.payload),
          ],
        ),
      ),
    );
  }

  @override
  Future<void> cancelAll() async {
    if (!_ready) return;
    // Documented no-op on unpackaged apps; harmless, and becomes real once
    // the app is shipped as MSIX in Phase 6.
    await _plugin.cancelAll();
  }

  @override
  Future<void> dispose() async {
    if (!_ready) return;
    _ready = false;
    await _plugin.cancelAll();
  }
}
