import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:mybrief/core/recurrence/recurrence_engine.dart';

void main() {
  tzdata.initializeTimeZones();

  final utc = tz.UTC;
  final london = tz.getLocation('Europe/London');

  group('tryParse', () {
    test('returns null for empty/invalid', () {
      expect(RecurrenceEngine.tryParse(null), isNull);
      expect(RecurrenceEngine.tryParse(''), isNull);
      expect(RecurrenceEngine.tryParse('nonsense'), isNull);
    });

    test('parses with and without RRULE prefix', () {
      expect(RecurrenceEngine.tryParse('FREQ=DAILY'), isNotNull);
      expect(RecurrenceEngine.tryParse('RRULE:FREQ=DAILY'), isNotNull);
    });
  });

  group('occurrencesUtc', () {
    test('non-recurring item returns its anchor in window', () {
      final start = DateTime.utc(2024, 1, 1, 9);
      final out = RecurrenceEngine.occurrencesUtc(
        startUtc: start,
        rule: null,
        fromUtc: DateTime.utc(2024, 1, 1),
        toUtc: DateTime.utc(2024, 1, 2),
        location: utc,
      );
      expect(out, [start]);

      final outside = RecurrenceEngine.occurrencesUtc(
        startUtc: start,
        rule: null,
        fromUtc: DateTime.utc(2024, 2, 1),
        toUtc: DateTime.utc(2024, 2, 2),
        location: utc,
      );
      expect(outside, isEmpty);
    });

    test('daily across three days', () {
      final out = RecurrenceEngine.occurrencesUtc(
        startUtc: DateTime.utc(2024, 1, 1, 9),
        rule: RecurrenceEngine.daily(),
        fromUtc: DateTime.utc(2024, 1, 1),
        toUtc: DateTime.utc(2024, 1, 3, 23, 59),
        location: utc,
      );
      expect(out, [
        DateTime.utc(2024, 1, 1, 9),
        DateTime.utc(2024, 1, 2, 9),
        DateTime.utc(2024, 1, 3, 9),
      ]);
    });

    test('weekly on Monday and Wednesday', () {
      final out = RecurrenceEngine.occurrencesUtc(
        startUtc: DateTime.utc(2024, 1, 1, 9), // Monday
        rule: RecurrenceEngine.weeklyOnDays(const [1, 3]),
        fromUtc: DateTime.utc(2024, 1, 1),
        toUtc: DateTime.utc(2024, 1, 10, 23, 59),
        location: utc,
      );
      expect(out.map((d) => [d.month, d.day]), [
        [1, 1],
        [1, 3],
        [1, 8],
        [1, 10],
      ]);
    });

    test('monthly on the 31st skips short months', () {
      final out = RecurrenceEngine.occurrencesUtc(
        startUtc: DateTime.utc(2024, 1, 31, 9),
        rule: RecurrenceEngine.monthly(),
        fromUtc: DateTime.utc(2024, 1, 31),
        toUtc: DateTime.utc(2024, 3, 31, 23, 59),
        location: utc,
      );
      // Feb 2024 has no 31st, so it jumps Jan -> Mar.
      expect(out.map((d) => [d.month, d.day]), [
        [1, 31],
        [3, 31],
      ]);
    });

    test('daily stays at the same local wall-clock across DST (Europe/London)',
        () {
      // 2024-03-31 is the UK spring-forward day (GMT -> BST).
      final out = RecurrenceEngine.occurrencesUtc(
        startUtc: DateTime.utc(2024, 3, 25, 9), // 09:00 London (GMT)
        rule: RecurrenceEngine.daily(),
        fromUtc: DateTime.utc(2024, 3, 25),
        toUtc: DateTime.utc(2024, 4, 1),
        location: london,
      );
      expect(out.length, 7); // Mar 25..31

      for (final occ in out) {
        final local = tz.TZDateTime.from(occ, london);
        expect(local.hour, 9,
            reason: 'local wall-clock must stay 09:00 through DST');
      }

      // Before the change 09:00 local == 09:00Z; after it == 08:00Z.
      expect(out.first, DateTime.utc(2024, 3, 25, 9));
      expect(out.last, DateTime.utc(2024, 3, 31, 8),
          reason: 'BST means 09:00 local is 08:00Z');
    });
  });

  group('nextAfter', () {
    test('non-recurring returns anchor only when future', () {
      final start = DateTime.utc(2024, 1, 1, 9);
      expect(
        RecurrenceEngine.nextAfter(
          startUtc: start,
          rule: null,
          afterUtc: DateTime.utc(2024, 1, 1),
          location: utc,
        ),
        start,
      );
      expect(
        RecurrenceEngine.nextAfter(
          startUtc: start,
          rule: null,
          afterUtc: DateTime.utc(2024, 1, 2),
          location: utc,
        ),
        isNull,
      );
    });

    test('daily advances by one day', () {
      final next = RecurrenceEngine.nextAfter(
        startUtc: DateTime.utc(2024, 1, 1, 9),
        rule: RecurrenceEngine.daily(),
        afterUtc: DateTime.utc(2024, 1, 1, 9),
        location: utc,
      );
      expect(next, DateTime.utc(2024, 1, 2, 9));
    });
  });
}
