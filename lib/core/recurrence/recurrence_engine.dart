import 'package:rrule/rrule.dart' as rrule;
import 'package:timezone/timezone.dart' as tz;

/// Recurrence expansion built on RFC 5545 (`package:rrule`).
///
/// `package:rrule` only works with UTC [DateTime]s, which would make a daily
/// "9am" reminder drift by an hour across a DST boundary. To stay wall-clock
/// stable we expand the rule on the *local wall-clock fields* (re-tagged as
/// pseudo-UTC) and then re-attach the real timezone to produce true UTC
/// instants. This is what keeps "every day at 09:00" at 09:00 local year-round.
class RecurrenceEngine {
  static rrule.RecurrenceRule? tryParse(String? raw) {
    if (raw == null) return null;
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (!s.toUpperCase().startsWith('RRULE:')) s = 'RRULE:$s';
    try {
      return rrule.RecurrenceRule.fromString(s);
    } catch (_) {
      return null;
    }
  }

  // ---- RRULE builders (used by the recurrence picker UI) ----
  static String daily({int interval = 1}) =>
      'RRULE:FREQ=DAILY;INTERVAL=$interval';

  static String weeklyOnDays(List<int> weekdays) {
    const codes = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
    final days = weekdays.map((d) => codes[(d - 1).clamp(0, 6)]).join(',');
    return 'RRULE:FREQ=WEEKLY;BYDAY=$days';
  }

  static String weekdays() => weeklyOnDays(const [1, 2, 3, 4, 5]);
  static String monthly() => 'RRULE:FREQ=MONTHLY';

  /// Occurrences within the inclusive window `[fromUtc, toUtc]`, returned as
  /// true UTC instants. A non-recurring item returns its single anchor when it
  /// falls inside the window.
  static List<DateTime> occurrencesUtc({
    required DateTime startUtc,
    String? rule,
    required DateTime fromUtc,
    required DateTime toUtc,
    required tz.Location location,
  }) {
    final start = tz.TZDateTime.from(startUtc, location);
    final from = tz.TZDateTime.from(fromUtc, location);
    final to = tz.TZDateTime.from(toUtc, location);

    final parsed = tryParse(rule);
    if (parsed == null) {
      final inRange = !start.isBefore(from) && !start.isAfter(to);
      return inRange ? [startUtc] : const [];
    }

    DateTime wall(DateTime d) => DateTime.utc(
        d.year, d.month, d.day, d.hour, d.minute, d.second, d.millisecond);

    final pStart = wall(start);
    final pFrom = wall(from);
    final pTo = wall(to);
    final after = pFrom.isAfter(pStart) ? pFrom : null;

    final instances = parsed.getInstances(
      start: pStart,
      after: after,
      includeAfter: true,
      before: pTo,
      includeBefore: true,
    );

    final result = <DateTime>[];
    for (final p in instances) {
      if (p.isBefore(pFrom) || p.isAfter(pTo)) continue;
      result.add(_toUtc(p, location));
    }
    return result;
  }

  /// The first occurrence strictly after [afterUtc], or null for a non-recurring
  /// anchor that is not in the future.
  static DateTime? nextAfter({
    required DateTime startUtc,
    String? rule,
    required DateTime afterUtc,
    required tz.Location location,
  }) {
    final start = tz.TZDateTime.from(startUtc, location);
    final after = tz.TZDateTime.from(afterUtc, location);

    final parsed = tryParse(rule);
    if (parsed == null) {
      return start.isAfter(after) ? startUtc : null;
    }

    DateTime wall(DateTime d) => DateTime.utc(
        d.year, d.month, d.day, d.hour, d.minute, d.second, d.millisecond);

    final pStart = wall(start);
    final pAfter = wall(after);
    final from = pAfter.isAfter(pStart) ? pAfter : pStart;

    final instances = parsed.getInstances(start: pStart, after: from);
    for (final p in instances) {
      final utc = _toUtc(p, location);
      if (utc.isAfter(afterUtc)) return utc;
    }
    return null;
  }

  static DateTime _toUtc(DateTime wall, tz.Location location) =>
      tz.TZDateTime(
        location,
        wall.year,
        wall.month,
        wall.day,
        wall.hour,
        wall.minute,
        wall.second,
        wall.millisecond,
      ).toUtc();
}
