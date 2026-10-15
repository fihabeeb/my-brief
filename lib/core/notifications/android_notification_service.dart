import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../time/app_timezone.dart';
import '../utils/logger.dart';
import 'notification_service.dart';

/// Android implementation.
///
/// Unlike Windows, Android can schedule: `AlarmManager` fires the notification
/// even if the app has been closed or the device rebooted, which is the only
/// way a mobile reminder is useful. That shifts responsibility for de-duplication
/// to this class — see `schedule`, which reports back whether the OS really
/// accepted the occurrence.
class AndroidNotificationService extends NotificationService {
  /// One channel for everything. Both reminders and due tasks are the same
  /// kind of thing to the user, and a single channel means they share one
  /// mute switch rather than scattering settings across the OS.
  static const _channelId = 'mybrief_alerts';
  static const _channelName = 'Reminders and due tasks';
  static const _channelDescription =
      'Alerts when a reminder comes due and when tasks are due today.';

  final _plugin = FlutterLocalNotificationsPlugin();
  AndroidFlutterLocalNotificationsPlugin? _android;
  bool _ready = false;
  bool _permissionRequested = false;
  void Function(String payload)? _onResponse;

  @override
  bool get isSupported => true;

  @override
  bool get supportsScheduling => true;

  @override
  Future<bool> init({required void Function(String payload) onResponse}) async {
    // Always refresh: the scheduler is rebuilt whenever a setting changes, and
    // the plugin can only be initialized once.
    _onResponse = onResponse;
    if (_ready) return true;

    _android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );

    final ok = await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _handleResponse,
    );
    _ready = ok ?? false;
    if (!_ready) return false;

    await _android?.createNotificationChannel(const AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
    ));

    await _requestNotificationPermission();
    return true;
  }

  /// Android 13+ needs POST_NOTIFICATIONS granted before anything is shown.
  ///
  /// Asked once, and only when notifications are not already enabled — the
  /// dialog is intrusive enough that it should not reappear on every rebuild.
  Future<void> _requestNotificationPermission() async {
    final android = _android;
    if (android == null || _permissionRequested) return;
    _permissionRequested = true;
    try {
      if (await android.areNotificationsEnabled() != true) {
        await android.requestNotificationsPermission();
      }
    } catch (e) {
      log.warning('Notification permission request failed: $e');
    }
  }

  /// Android returns the pressed action's id separately from the notification
  /// payload — unlike Windows, where both collapse to the same string. An
  /// action must therefore win over the payload, or tapping "Snooze" would
  /// merely navigate to the reminders list.
  void _handleResponse(NotificationResponse response) {
    final actionId = response.actionId;
    final value = (actionId != null && actionId.isNotEmpty)
        ? actionId
        : (response.payload ?? '');
    _onResponse?.call(value);
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
        android: _details(request),
      ),
    );
  }

  @override
  Future<bool> schedule(NotificationRequest request, DateTime when) async {
    if (!_ready || _android == null) return false;
    // AlarmManager works in absolute time; convert from the stored UTC instant
    // into the device's zone so a DST shift cannot move a reminder by an hour.
    final scheduledDate = tz.TZDateTime.from(when, AppTimezone.location);
    final mode = await _scheduleMode();

    try {
      await _zonedSchedule(request, scheduledDate, mode);
      return true;
    } catch (e) {
      if (mode == AndroidScheduleMode.inexactAllowWhileIdle) {
        log.warning('Notification scheduling failed: $e');
        return false;
      }
      // Exact alarms need a permission Android 14+ revokes by default. A
      // slightly late reminder still beats a missing one, so fall back rather
      // than dropping it — and report success only if the fallback lands.
      try {
        await _zonedSchedule(
          request,
          scheduledDate,
          AndroidScheduleMode.inexactAllowWhileIdle,
        );
        return true;
      } catch (_) {
        log.warning('Notification scheduling failed for ${request.id}: $e');
        return false;
      }
    }
  }

  Future<void> _zonedSchedule(
    NotificationRequest request,
    tz.TZDateTime scheduledDate,
    AndroidScheduleMode mode,
  ) {
    return _plugin.zonedSchedule(
      id: request.id,
      title: request.title,
      body: request.body,
      scheduledDate: scheduledDate,
      androidScheduleMode: mode,
      payload: request.payload,
      notificationDetails: NotificationDetails(
        android: _details(request),
      ),
    );
  }

  /// Exact when permitted, inexact otherwise.
  ///
  /// Checked rather than assumed, so a device where the user has revoked exact
  /// alarms is detected up front instead of throwing on every schedule. Any
  /// failure of the check errs towards exact, which [schedule] then downgrades.
  Future<AndroidScheduleMode> _scheduleMode() async {
    try {
      if (await _android?.canScheduleExactNotifications() == false) {
        return AndroidScheduleMode.inexactAllowWhileIdle;
      }
    } catch (_) {
      // Check unsupported on this API level; let scheduling itself decide.
    }
    return AndroidScheduleMode.exactAllowWhileIdle;
  }

  AndroidNotificationDetails _details(NotificationRequest request) =>
      AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        // The collapsed body drops newlines, so a grouped digest would show as
        // one run-together line; the expanded form keeps each task on its own.
        styleInformation: BigTextStyleInformation(request.body),
        actions: [
          for (final a in request.actions)
            AndroidNotificationAction(
              // The action id is what comes back, so it carries the complete
              // intent rather than a reference to this notification.
              a.payload,
              a.label,
              // Launches the app, which Android 12+ requires for action
              // buttons to appear at all while the app is backgrounded.
              showsUserInterface: true,
            ),
        ],
      );

  @override
  Future<void> cancel(int id) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: id);
    } catch (e) {
      log.warning('Notification cancel failed for $id: $e');
    }
  }

  @override
  Future<void> cancelAll() async {
    if (!_ready) return;
    await _plugin.cancelAll();
  }

  @override
  Future<void> dispose() async {
    if (!_ready) return;
    _ready = false;
    await _plugin.cancelAll();
  }
}
