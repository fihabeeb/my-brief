import 'package:flutter_test/flutter_test.dart';

import 'package:mybrief/core/notifications/notification_intent.dart';

void main() {
  group('NotificationIntent codec', () {
    test('nav round-trips', () {
      final intent = const NavIntent('/reminders');
      final parsed = NotificationIntent.parse(intent.encode());

      expect(parsed, isA<NavIntent>());
      parsed as NavIntent;
      expect(parsed.route, '/reminders');
    });

    test('snooze round-trips id and minutes', () {
      final parsed = NotificationIntent.parse(
        const SnoozeIntent('abc-123', 15).encode(),
      );

      expect(parsed, isA<SnoozeIntent>());
      parsed as SnoozeIntent;
      expect(parsed.reminderId, 'abc-123');
      expect(parsed.minutes, 15);
    });

    test('done round-trips', () {
      final parsed = NotificationIntent.parse(const DoneIntent('abc-123').encode());

      expect(parsed, isA<DoneIntent>());
      parsed as DoneIntent;
      expect(parsed.reminderId, 'abc-123');
    });

    test('an empty payload means "open the app"', () {
      expect(NotificationIntent.parse(NotificationIntent.openApp),
          isA<OpenAppIntent>());
      expect(NotificationIntent.parse(''), isA<OpenAppIntent>());
    });

    test('unknown or mangled payloads fall back to opening the app', () {
      // Windows can hand back anything; falling back beats throwing or
      // silently doing nothing.
      for (final raw in [
        'garbage',
        'nav:',
        'done:',
        'snooze:',
        'snooze:id-without-minutes',
        'snooze:id:not-a-number',
        'NAVO:/reminders',
      ]) {
        expect(NotificationIntent.parse(raw), isA<OpenAppIntent>(),
            reason: 'expected fallback for "$raw"');
      }
    });

    test('ids containing a colon are not produced by this app', () {
      // The codec splits on ':', which is safe only because ids are UUIDs.
      expect(const SnoozeIntent('0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0', 10)
              .encode(),
          'snooze:0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0:10');
    });
  });

  group('NotificationAction', () {
    test('exposes its intent as the payload the platform returns', () {
      const action =
          NotificationAction(label: 'Done', intent: DoneIntent('r1'));

      expect(action.payload, 'done:r1');
      expect(NotificationIntent.parse(action.payload), isA<DoneIntent>());
    });
  });
}
