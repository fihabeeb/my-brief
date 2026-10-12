import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Timezone bootstrap.
///
/// Phase 1 defaults to UTC so date-only recurrence is unambiguous. Phase 2
/// (notifications) upgrades [location] to the real device zone via
/// `flutter_timezone`, which is when DST-correct reminder firing matters.
class AppTimezone {
  static bool _inited = false;

  static void init() {
    if (_inited) return;
    tzdata.initializeTimeZones();
    _inited = true;
  }

  static tz.Location get location {
    init();
    return tz.UTC;
  }
}
