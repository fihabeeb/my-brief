import 'package:flutter_test/flutter_test.dart';

import 'package:mybrief/features/dashboard/dashboard_providers.dart';

void main() {
  group('dayStartFor', () {
    test('the day begins at the reset hour, not at midnight', () {
      expect(
        dayStartFor(DateTime(2026, 6, 15, 12), resetHour: 6),
        DateTime(2026, 6, 15, 6),
      );
      expect(
        dayStartFor(DateTime(2026, 6, 15, 6), resetHour: 6),
        DateTime(2026, 6, 15, 6),
        reason: 'the reset instant belongs to the day it starts',
      );
    });

    test('before the reset hour the running day began yesterday', () {
      expect(
        dayStartFor(DateTime(2026, 6, 15, 2), resetHour: 6),
        DateTime(2026, 6, 14, 6),
        reason: 'a digest read at 02:00 still describes the day begun '
            'yesterday morning, not one that has not started',
      );
      // The instant one millisecond before the reset still rolls back.
      expect(
        dayStartFor(DateTime(2026, 6, 15, 5, 59, 59, 999), resetHour: 6),
        DateTime(2026, 6, 14, 6),
      );
    });

    test('crosses a month and a year boundary', () {
      expect(
        dayStartFor(DateTime(2026, 3, 1, 3), resetHour: 6),
        DateTime(2026, 2, 28, 6),
      );
      expect(
        dayStartFor(DateTime(2027, 1, 1, 0), resetHour: 6),
        DateTime(2026, 12, 31, 6),
      );
    });

    test('honours a non-default reset hour', () {
      expect(
        dayStartFor(DateTime(2026, 6, 15, 23), resetHour: 21),
        DateTime(2026, 6, 15, 21),
      );
      expect(
        dayStartFor(DateTime(2026, 6, 15, 20), resetHour: 21),
        DateTime(2026, 6, 14, 21),
      );
    });
  });

  group('digestDue', () {
    // 10:00 on the 15th: comfortably past a 06:00 reset.
    final now = DateTime(2026, 6, 15, 10);

    test('is due when it has never been shown', () {
      expect(digestDue(now: now, lastShown: null, resetHour: 6), isTrue);
    });

    test('is due once shown earlier than the current day start', () {
      expect(
        digestDue(now: now, lastShown: DateTime(2026, 6, 14, 7), resetHour: 6),
        isTrue,
        reason: 'the 07:00 view belonged to the day that has since rolled over',
      );
    });

    test('is not due when already shown for this day', () {
      expect(
        digestDue(now: now, lastShown: DateTime(2026, 6, 15, 6), resetHour: 6),
        isFalse,
      );
      expect(
        digestDue(now: now, lastShown: now, resetHour: 6),
        isFalse,
      );
    });

    test('a pre-dawn open belongs to yesterday, so yesterday counts as due', () {
      final preDawn = DateTime(2026, 6, 15, 2);
      // The running day started at 06:00 on the 14th, so a digest shown at
      // 07:00 on the 14th is already *this* day's and must not repeat.
      expect(
        digestDue(now: preDawn, lastShown: DateTime(2026, 6, 14, 7),
            resetHour: 6),
        isFalse,
      );
      // Shown on the 13th, it has rolled over.
      expect(
        digestDue(now: preDawn, lastShown: DateTime(2026, 6, 13, 7),
            resetHour: 6),
        isTrue,
      );
    });
  });

  group('TodayProgress', () {
    test('is empty rather than undefined when nothing is due', () {
      const progress = TodayProgress(done: 0, open: 0);
      expect(progress.isEmpty, isTrue);
      expect(progress.total, 0);
      expect(progress.fraction, 0,
          reason: 'an empty day must not divide by zero');
    });

    test('measures the share of today that is finished', () {
      expect(const TodayProgress(done: 2, open: 6).fraction, 0.25);
      expect(const TodayProgress(done: 6, open: 2).fraction, 0.75);
      expect(const TodayProgress(done: 3, open: 0).fraction, 1);
    });
  });
}
