import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kNotificationsEnabled = 'notifications_enabled';
const _kTaskNotifyHour = 'task_notify_hour';
const _kMinimizeToTray = 'minimize_to_tray';
const _kStartOnLogin = 'start_on_login';
const _kSnoozeMinutes = 'snooze_minutes';

/// Device-local preferences.
///
/// Deliberately *not* stored in Supabase: start-on-login and minimise-to-tray
/// describe this machine, and the notification scheduler runs against this
/// machine's clock — so a phone changing these must not rewrite Windows'.
class AppSettings {
  const AppSettings({
    this.notificationsEnabled = true,
    this.taskNotifyHour = 9,
    this.minimizeToTray = true,
    this.startOnLogin = false,
    this.snoozeMinutes = 10,
  });

  /// Master switch for all local notifications.
  final bool notificationsEnabled;

  /// Local wall-clock hour (0-23) at which "due today" tasks are announced.
  /// Tasks are date-only in the DB, so this is the time they get a time.
  final int taskNotifyHour;

  /// Closing the window hides it in the tray instead of exiting.
  final bool minimizeToTray;

  /// Launch at login (launch_at_startup / Windows registry).
  final bool startOnLogin;

  /// Default snooze length offered on a reminder notification.
  final int snoozeMinutes;

  AppSettings copyWith({
    bool? notificationsEnabled,
    int? taskNotifyHour,
    bool? minimizeToTray,
    bool? startOnLogin,
    int? snoozeMinutes,
  }) {
    return AppSettings(
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      taskNotifyHour: taskNotifyHour ?? this.taskNotifyHour,
      minimizeToTray: minimizeToTray ?? this.minimizeToTray,
      startOnLogin: startOnLogin ?? this.startOnLogin,
      snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
    );
  }

  static AppSettings read(SharedPreferences prefs) => AppSettings(
        notificationsEnabled:
            prefs.getBool(_kNotificationsEnabled) ?? const AppSettings().notificationsEnabled,
        taskNotifyHour:
            prefs.getInt(_kTaskNotifyHour) ?? const AppSettings().taskNotifyHour,
        minimizeToTray:
            prefs.getBool(_kMinimizeToTray) ?? const AppSettings().minimizeToTray,
        startOnLogin:
            prefs.getBool(_kStartOnLogin) ?? const AppSettings().startOnLogin,
        snoozeMinutes:
            prefs.getInt(_kSnoozeMinutes) ?? const AppSettings().snoozeMinutes,
      );
}

/// Overridden in `main()` with a loaded instance so settings read synchronously
/// (no async gap on first frame).
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'Override sharedPreferencesProvider in main() with SharedPreferences.getInstance().',
  ),
);

class AppSettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => AppSettings.read(ref.read(sharedPreferencesProvider));

  void setNotificationsEnabled(bool value) {
    state = state.copyWith(notificationsEnabled: value);
    _save((p) => p.setBool(_kNotificationsEnabled, value));
  }

  void setTaskNotifyHour(int hour) {
    state = state.copyWith(taskNotifyHour: hour.clamp(0, 23));
    _save((p) => p.setInt(_kTaskNotifyHour, hour.clamp(0, 23)));
  }

  void setMinimizeToTray(bool value) {
    state = state.copyWith(minimizeToTray: value);
    _save((p) => p.setBool(_kMinimizeToTray, value));
  }

  void setStartOnLogin(bool value) {
    state = state.copyWith(startOnLogin: value);
    _save((p) => p.setBool(_kStartOnLogin, value));
  }

  void setSnoozeMinutes(int minutes) {
    state = state.copyWith(snoozeMinutes: minutes.clamp(1, 240));
    _save((p) => p.setInt(_kSnoozeMinutes, minutes.clamp(1, 240)));
  }

  Future<void> _save(Future<bool> Function(SharedPreferences) write) =>
      write(ref.read(sharedPreferencesProvider));
}

final appSettingsProvider =
    NotifierProvider<AppSettingsController, AppSettings>(AppSettingsController.new);
