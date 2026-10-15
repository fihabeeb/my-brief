import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:mybrief/core/notifications/due_planner.dart';
import 'package:mybrief/core/notifications/notification_intent.dart';

void main() {
  tzdata.initializeTimeZones();
  final london = tz.getLocation('Europe/London');

  const hour = 9;
  final planner =
      DuePlanner(location: london, taskNotifyHour: hour, snoozeMinutes: 10);

  List<PlannedNotification> plan({
    List<ReminderInput> reminders = const [],
    List<TaskInput> tasks = const [],
    required DateTime now,
    Set<String> delivered = const {},
  }) =>
      planner.plan(
        reminders: reminders,
        tasks: tasks,
        now: now,
        delivered: delivered,
      );

  ReminderInput reminder({
    String id = 'r1',
    String title = 'Call Sam',
    required DateTime remindAt,
    String status = 'upcoming',
    DateTime? snoozedUntil,
    String? notes,
  }) =>
      ReminderInput(
        id: id,
        title: title,
        notes: notes,
        remindAt: remindAt,
        status: status,
        snoozedUntil: snoozedUntil,
      );

  TaskInput task({
    String id = 't1',
    String title = 'Pay bill',
    required DateTime dueDate,
    String status = 'pending',
  }) =>
      TaskInput(id: id, title: title, dueDate: dueDate, status: status);

  int localHour(DateTime utc) => tz.TZDateTime.from(utc, london).hour;

  group('reminders', () {
    test('a future reminder is planned for its own fire time', () {
      final now = DateTime.utc(2026, 6, 15, 7);
      final remindAt = DateTime.utc(2026, 6, 15, 9);

      final out = plan(
        reminders: [reminder(remindAt: remindAt)],
        now: now,
      );

      expect(out, hasLength(1));
      expect(out.single.fireAt, remindAt);
      expect(out.single.fireAt.isAfter(now), isTrue);
      expect(out.single.title, 'Call Sam');
      expect(out.single.onOpen, const NavIntent('/reminders'));
    });

    test('an overdue reminder is due immediately', () {
      final now = DateTime.utc(2026, 6, 15, 12);

      final out = plan(
        reminders: [reminder(remindAt: DateTime.utc(2026, 6, 15, 9))],
        now: now,
      );

      expect(out.single.fireAt.isAfter(now), isFalse,
          reason: 'a missed reminder must fire on the next evaluation');
    });

    test('a delivered occurrence is never planned again', () {
      final remindAt = DateTime.utc(2026, 6, 15, 9);
      final key = 'reminder:r1:${remindAt.millisecondsSinceEpoch}';

      final out = plan(
        reminders: [reminder(remindAt: remindAt)],
        now: DateTime.utc(2026, 6, 15, 10),
        delivered: {key},
      );

      expect(out, isEmpty);
    });

    test('a completed reminder is skipped', () {
      final out = plan(
        reminders: [
          reminder(
            remindAt: DateTime.utc(2026, 6, 15, 9),
            status: 'completed',
          ),
        ],
        now: DateTime.utc(2026, 6, 15, 10),
      );

      expect(out, isEmpty);
    });

    test('a snoozed reminder fires at snoozedUntil, not remindAt', () {
      final remindAt = DateTime.utc(2026, 6, 15, 9);
      final snoozedUntil = DateTime.utc(2026, 6, 15, 9, 10);
      // The original occurrence was already announced…
      final delivered = {'reminder:r1:${remindAt.millisecondsSinceEpoch}'};

      final out = plan(
        reminders: [
          reminder(remindAt: remindAt, snoozedUntil: snoozedUntil),
        ],
        now: DateTime.utc(2026, 6, 15, 9, 5),
        delivered: delivered,
      );

      expect(out, hasLength(1),
          reason: 'the snooze target is a different occurrence, so it still fires');
      expect(out.single.fireAt, snoozedUntil);

      // …and once the snooze itself has fired, it stops.
      final again = plan(
        reminders: [
          reminder(remindAt: remindAt, snoozedUntil: snoozedUntil),
        ],
        now: DateTime.utc(2026, 6, 15, 9, 20),
        delivered: {...delivered, 'reminder:r1:${snoozedUntil.millisecondsSinceEpoch}'},
      );
      expect(again, isEmpty);
    });

    test('carries snooze and done actions with usable payloads', () {
      final out = plan(
        reminders: [reminder(remindAt: DateTime.utc(2026, 6, 15, 9))],
        now: DateTime.utc(2026, 6, 15, 10),
      );

      final actions = out.single.actions;
      expect(actions.map((a) => a.label), containsAll(['Snooze 10m', 'Done']));

      final snooze = NotificationIntent.parse(actions[0].payload);
      expect(snooze, isA<SnoozeIntent>());
      snooze as SnoozeIntent;
      expect(snooze.reminderId, 'r1');
      expect(snooze.minutes, 10);

      expect(NotificationIntent.parse(actions[1].payload), isA<DoneIntent>());
    });

    test('notes are used as the body when present', () {
      final out = plan(
        reminders: [
          reminder(
            remindAt: DateTime.utc(2026, 6, 15, 9),
            notes: 'Bring the charger',
          ),
        ],
        now: DateTime.utc(2026, 6, 15, 10),
      );

      expect(out.single.body, 'Bring the charger');
    });
  });

  group('tasks', () {
    test('fires at the configured local hour on the due date', () {
      // Mid-winter: London runs on GMT (UTC+0).
      final now = DateTime.utc(2026, 1, 15, 7);

      final out = plan(
        tasks: [task(dueDate: DateTime.utc(2026, 1, 15))],
        now: now,
      );

      expect(out.single.fireAt, DateTime.utc(2026, 1, 15, hour));
      expect(localHour(out.single.fireAt), hour);
    });

    test('the local hour holds across DST', () {
      // Mid-summer: London runs on BST (UTC+1), so 09:00 local is 08:00 UTC.
      final now = DateTime.utc(2026, 7, 15, 7);

      final out = plan(
        tasks: [task(dueDate: DateTime.utc(2026, 7, 15))],
        now: now,
      );

      expect(out.single.fireAt, DateTime.utc(2026, 7, 15, 8));
      expect(localHour(out.single.fireAt), hour,
          reason: 'a 9am alert must stay at 9am local, not shift with UTC');
    });

    test('a future task waits for its own date', () {
      final now = DateTime.utc(2026, 1, 15, 7);

      final out = plan(
        tasks: [task(dueDate: DateTime.utc(2026, 1, 17))],
        now: now,
      );

      expect(out.single.fireAt, DateTime.utc(2026, 1, 17, hour));
      expect(out.single.fireAt.isAfter(now), isTrue);
    });

    test('an overdue task waits for the next slot instead of firing at 3am', () {
      final now = DateTime.utc(2026, 1, 15, 7);

      final out = plan(
        tasks: [task(dueDate: DateTime.utc(2026, 1, 10))],
        now: now,
      );

      expect(out.single.fireAt, DateTime.utc(2026, 1, 15, hour),
          reason: 'an overdue task should not alert the instant the app opens');
      expect(out.single.fireAt.isAfter(now), isTrue);
    });

    test('an overdue task becomes due once the slot passes', () {
      final now = DateTime.utc(2026, 1, 15, 9, 30);

      final out = plan(
        tasks: [task(dueDate: DateTime.utc(2026, 1, 10))],
        now: now,
      );

      expect(out.single.fireAt.isAfter(now), isFalse);
    });

    test('an overdue task is announced once, not every following day', () {
      final dueDate = DateTime.utc(2026, 1, 10);
      final key = 'task:t1:${dueDate.millisecondsSinceEpoch}';

      final out = plan(
        tasks: [task(dueDate: dueDate)],
        now: DateTime.utc(2026, 1, 20, 10),
        delivered: {key},
      );

      expect(out, isEmpty);
    });

    test('completed and delivered tasks are skipped', () {
      expect(
        plan(
          tasks: [
            task(dueDate: DateTime.utc(2026, 1, 15), status: 'completed'),
          ],
          now: DateTime.utc(2026, 1, 15, 10),
        ),
        isEmpty,
      );

      final dueDate = DateTime.utc(2026, 1, 15);
      expect(
        plan(
          tasks: [task(dueDate: dueDate)],
          now: DateTime.utc(2026, 1, 15, 10),
          delivered: {'task:t1:${dueDate.millisecondsSinceEpoch}'},
        ),
        isEmpty,
      );
    });
  });

  test('plans come back sorted by fire time', () {
    final out = plan(
      reminders: [
        reminder(id: 'a', remindAt: DateTime.utc(2026, 6, 15, 11)),
        reminder(id: 'b', remindAt: DateTime.utc(2026, 6, 15, 9)),
      ],
      // Overdue by a day, so it lands in today's 09:00 slot — which in June
      // (BST) is 08:00 UTC, i.e. the earliest of the three.
      tasks: [task(id: 'c', dueDate: DateTime.utc(2026, 6, 14))],
      now: DateTime.utc(2026, 6, 15, 8),
    );

    expect(out.map((p) => p.itemId), ['c', 'b', 'a']);
    for (var i = 1; i < out.length; i++) {
      expect(
        out[i].fireAt.isAfter(out[i - 1].fireAt),
        isTrue,
        reason: 'the scheduler arms its timer from the first element',
      );
    }
  });

  test('a due date is taken from its UTC calendar day', () {
    // The column holds UTC midnight, and the database returns that same
    // instant in the device's own zone. The calendar day therefore has to come
    // from the UTC side of the value: on a machine west of UTC the local day
    // of that instant is the 15th, and reading it directly would announce a
    // task due on the 16th a day early.
    final stored = DateTime.fromMillisecondsSinceEpoch(
      DateTime.utc(2026, 6, 16).millisecondsSinceEpoch,
    );

    final out = plan(
      tasks: [task(id: 't1', dueDate: stored)],
      now: DateTime.utc(2026, 6, 15, 8),
    );

    expect(out, hasLength(1));
    expect(
      out.single.fireAt.toUtc(),
      DateTime.utc(2026, 6, 16, 8),
      reason: '09:00 BST on the 16th',
    );
  });
}
