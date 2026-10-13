import 'package:flutter/foundation.dart';

/// What a notification interaction asks the app to do.
///
/// Each intent encodes itself into a single string, because Windows returns the
/// pressed button's `arguments` as *both* `payload` and `actionId` — a toast
/// string must therefore carry its complete intent, never a reference to the
/// notification it belongs to.
@immutable
sealed class NotificationIntent {
  const NotificationIntent();

  static const _nav = 'nav:';
  static const _snooze = 'snooze:';
  static const _done = 'done:';

  /// Encode form of [OpenAppIntent] (empty string = "just open the app").
  static const String openApp = '';

  static String nav(String route) => '$_nav$route';
  static String snooze(String reminderId, int minutes) =>
      '$_snooze$reminderId:$minutes';
  static String done(String reminderId) => '$_done$reminderId';

  String encode();

  /// Decodes a toast payload. Unknown values fall back to opening the app, so
  /// a malformed or platform-mangled string still does something useful.
  factory NotificationIntent.parse(String raw) {
    if (raw.startsWith(_nav)) {
      final route = raw.substring(_nav.length);
      return route.isEmpty ? const OpenAppIntent() : NavIntent(route);
    }
    if (raw.startsWith(_snooze)) {
      final rest = raw.substring(_snooze.length);
      final cut = rest.lastIndexOf(':');
      if (cut > 0) {
        final minutes = int.tryParse(rest.substring(cut + 1));
        if (minutes != null) {
          return SnoozeIntent(rest.substring(0, cut), minutes);
        }
      }
      return const OpenAppIntent();
    }
    if (raw.startsWith(_done)) {
      final id = raw.substring(_done.length);
      return id.isEmpty ? const OpenAppIntent() : DoneIntent(id);
    }
    return const OpenAppIntent();
  }
}

/// Bring the window forward without navigating.
class OpenAppIntent extends NotificationIntent {
  const OpenAppIntent();

  @override
  String encode() => NotificationIntent.openApp;
}

/// Bring the window forward and go to [route].
class NavIntent extends NotificationIntent {
  const NavIntent(this.route);

  final String route;

  @override
  String encode() => NotificationIntent.nav(route);
}

/// Snooze this reminder for [minutes].
class SnoozeIntent extends NotificationIntent {
  const SnoozeIntent(this.reminderId, this.minutes);

  final String reminderId;
  final int minutes;

  @override
  String encode() => NotificationIntent.snooze(reminderId, minutes);
}

/// Complete this reminder (recurring ones roll forward instead).
class DoneIntent extends NotificationIntent {
  const DoneIntent(this.reminderId);

  final String reminderId;

  @override
  String encode() => NotificationIntent.done(reminderId);
}

/// A button attached to a toast.
@immutable
class NotificationAction {
  const NotificationAction({required this.label, required this.intent});

  final String label;
  final NotificationIntent intent;

  /// The string the platform returns when this button is pressed.
  String get payload => intent.encode();
}
