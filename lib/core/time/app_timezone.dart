import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Timezone bootstrap.
///
/// [init] resolves the device's IANA zone once at startup so recurrence and
/// "notify at 09:00" follow local wall-clock time across DST. Until it
/// completes — and always in tests, which never call it — [location] returns
/// UTC, which keeps tests deterministic on any machine.
class AppTimezone {
  static tz.Location _zone = tz.UTC;
  static bool _tzdataReady = false;
  static bool _resolved = false;

  /// Resolves the device timezone. Call once from `main()` before `runApp`.
  /// Never throws: on failure we simply stay on UTC.
  static Future<void> init() async {
    if (_resolved) return;
    _ensureTzdata();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      _zone = tz.getLocation(info.identifier);
    } catch (_) {
      _zone = tz.UTC;
    } finally {
      _resolved = true;
    }
  }

  static tz.Location get location {
    _ensureTzdata();
    return _zone;
  }

  static void _ensureTzdata() {
    if (_tzdataReady) return;
    tzdata.initializeTimeZones();
    _tzdataReady = true;
  }
}
