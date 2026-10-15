import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:mybrief/core/data/reminder_repository.dart';
import 'package:mybrief/core/data/task_repository.dart';
import 'package:mybrief/core/database/app_database.dart';
import 'package:mybrief/core/notifications/due_planner.dart';
import 'package:mybrief/core/notifications/notification_intent.dart';
import 'package:mybrief/core/notifications/notification_scheduler.dart';
import 'package:mybrief/core/notifications/notification_service.dart';

/// Stands in for a platform: records what was shown, never throws.
///
/// With [scheduling] on it behaves like Android, where the OS owns future
/// occurrences; off it behaves like Windows, where everything is shown at once.
class _RecordingService extends NotificationService {
  _RecordingService({this.scheduling = false});

  final bool scheduling;
  final shown = <NotificationRequest>[];
  final scheduled = <(NotificationRequest, DateTime)>[];
  final cancelled = <int>[];

  /// Lets a test simulate the OS refusing to schedule (permission revoked).
  bool acceptSchedules = true;
  void Function(String payload)? onResponse;

  @override
  bool get isSupported => true;

  @override
  bool get supportsScheduling => scheduling;

  @override
  Future<bool> init({required void Function(String payload) onResponse}) async {
    this.onResponse = onResponse;
    return true;
  }

  @override
  Future<void> show(NotificationRequest request) async => shown.add(request);

  @override
  Future<bool> schedule(NotificationRequest request, DateTime when) async {
    if (!scheduling || !acceptSchedules) return false;
    scheduled.add((request, when));
    return true;
  }

  @override
  Future<void> cancel(int id) async => cancelled.add(id);

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  tzdata.initializeTimeZones();

  late AppDatabase db;
  late TaskRepository tasks;
  late ReminderRepository reminders;
  late _RecordingService service;
  late SharedPreferences prefs;

  /// Fixed, injected clock — tests move it forward instead of sleeping.
  late DateTime now;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tasks = TaskRepository(db);
    reminders = ReminderRepository(db);
    service = _RecordingService();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    now = DateTime.utc(2026, 6, 15, 8);
  });

  tearDown(() => db.close());

  NotificationScheduler buildScheduler({NotificationService? using}) {
    final scheduler = NotificationScheduler(
      service: using ?? service,
      reminders: reminders,
      tasks: tasks,
      prefs: prefs,
      // UTC keeps the expectations in this file arithmetic-simple; local-hour
      // behaviour is covered by due_planner_test.dart.
      planner: DuePlanner(
        location: tz.UTC,
        taskNotifyHour: 9,
        snoozeMinutes: 10,
      ),
      onActivate: () async {},
      onNavigate: (_) {},
      clock: () => now,
    );
    addTearDown(scheduler.stop);
    return scheduler;
  }

  test('announces a due reminder exactly once, however often it evaluates',
      () async {
    await reminders.upsert(
      userId: 'u1',
      title: 'Call Sam',
      remindAt: now.subtract(const Duration(minutes: 1)),
    );

    final scheduler = buildScheduler();
    await scheduler.start();

    expect(service.shown, hasLength(1));
    expect(service.shown.single.title, 'Call Sam');
    expect(service.shown.single.actions, hasLength(2),
        reason: 'reminder toasts carry snooze + done');

    // Two more evaluations (as a second database stream would trigger).
    await scheduler.evaluate();
    await scheduler.evaluate();

    expect(service.shown, hasLength(1),
        reason: 'a delivered occurrence must never be re-announced');
  });

  test('a reminder set for later does not fire until its time', () async {
    await reminders.upsert(
      userId: 'u1',
      title: 'Later',
      remindAt: now.add(const Duration(hours: 1)),
    );

    final scheduler = buildScheduler();
    await scheduler.start();
    expect(service.shown, isEmpty);

    now = now.add(const Duration(hours: 1, minutes: 1));
    await scheduler.evaluate();

    expect(service.shown, hasLength(1));
    expect(service.shown.single.title, 'Later');
  });

  test('due tasks collapse into a single grouped toast', () async {
    await tasks.upsert(
        userId: 'u1', title: 'Pay bill', dueDate: DateTime.utc(2026, 6, 15));
    await tasks.upsert(
        userId: 'u1',
        title: 'Send invoice',
        dueDate: DateTime.utc(2026, 6, 15));
    await tasks.upsert(
        userId: 'u1',
        title: 'Book dentist',
        dueDate: DateTime.utc(2026, 6, 14)); // overdue -> today's slot

    // Just past the 09:00 slot, so all three are due.
    now = DateTime.utc(2026, 6, 15, 9, 30);

    final scheduler = buildScheduler();
    await scheduler.start();

    expect(service.shown, hasLength(1),
        reason: 'three separate toasts would bury the screen');
    expect(service.shown.single.title, '3 tasks due');
    expect(service.shown.single.body.split('\n'), hasLength(3));
    expect(service.shown.single.payload, 'nav:/tasks');
  });

  test('task alerts respect the configured hour', () async {
    await tasks.upsert(
        userId: 'u1', title: 'Pay bill', dueDate: DateTime.utc(2026, 6, 15));
    now = DateTime.utc(2026, 6, 15, 7);

    final scheduler = buildScheduler();
    await scheduler.start();
    expect(service.shown, isEmpty, reason: 'before the 09:00 slot');

    now = DateTime.utc(2026, 6, 15, 18);
    await scheduler.evaluate();
    expect(service.shown, hasLength(1));
  });

  test('a snooze action pushes the reminder forward', () async {
    await reminders.upsert(
      userId: 'u1',
      title: 'Call Sam',
      remindAt: now.subtract(const Duration(minutes: 1)),
    );

    final scheduler = buildScheduler();
    await scheduler.start();
    expect(service.shown, hasLength(1));

    final id = (await reminders.watchActive().first).single.id;
    await scheduler.handleIntent(SnoozeIntent(id, 10));

    final row = (await reminders.watchActive().first).single;
    expect(row.snoozedUntil, isNotNull,
        reason: 'the toast action must reach the repository');
    expect(row.status, 'upcoming');

    await scheduler.evaluate();
    expect(service.shown, hasLength(1),
        reason: 'the snoozed occurrence is still in the future');
  });

  test('a done action completes the reminder and stops further alerts',
      () async {
    await reminders.upsert(
      userId: 'u1',
      title: 'Call Sam',
      remindAt: now.subtract(const Duration(minutes: 1)),
    );

    final scheduler = buildScheduler();
    await scheduler.start();
    expect(service.shown, hasLength(1));

    final id = (await reminders.watchActive().first).single.id;
    await scheduler.handleIntent(DoneIntent(id));

    final row = (await reminders.watchActive().first).single;
    expect(row.status, 'completed');
    expect(row.completedAt, isNotNull);

    await scheduler.evaluate();
    expect(service.shown, hasLength(1));
  });

  test('a nav action navigates and brings the window forward', () async {
    final activated = <void>[];
    final routes = <String>[];

    final scheduler = NotificationScheduler(
      service: service,
      reminders: reminders,
      tasks: tasks,
      prefs: prefs,
      planner: DuePlanner(
        location: tz.UTC,
        taskNotifyHour: 9,
        snoozeMinutes: 10,
      ),
      onActivate: () async => activated.add(null),
      onNavigate: routes.add,
      clock: () => now,
    );
    addTearDown(scheduler.stop);
    await scheduler.start();

    await scheduler.handleIntent(const NavIntent('/tasks'));

    expect(activated, hasLength(1));
    expect(routes, ['/tasks']);
  });

  test('forgets a delivered key once its reminder is deleted', () async {
    await reminders.upsert(
      userId: 'u1',
      title: 'Call Sam',
      remindAt: now.subtract(const Duration(minutes: 1)),
    );

    final scheduler = buildScheduler();
    await scheduler.start();
    expect(service.shown, hasLength(1));

    final id = (await reminders.watchActive().first).single.id;
    expect(prefs.getString('delivered_notifications'), contains(id));

    await reminders.softDelete(id);
    // Let the stream deliver the deletion (which queues its own evaluate),
    // then make sure the prune has been persisted.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await scheduler.evaluate();

    expect(prefs.getString('delivered_notifications'), isNot(contains(id)),
        reason: 'keys for deleted items must not accumulate forever');
  });

  test('a corrupt delivered store is repaired, not fatal', () async {
    await prefs.setString('delivered_notifications', 'not json');
    await reminders.upsert(
      userId: 'u1',
      title: 'Call Sam',
      remindAt: now.subtract(const Duration(minutes: 1)),
    );

    final scheduler = buildScheduler();
    await scheduler.start();

    expect(service.shown, hasLength(1),
        reason: 'a bad prefs value should cost one duplicate, not all alerts');
    expect(prefs.getString('delivered_notifications'), contains('reminder:'));
  });

  // Android hands future occurrences to AlarmManager so they fire with the app
  // closed. These cover the one behaviour that differs from Windows: who owns
  // the notification, and what is recorded when they do.
  group('on a platform that schedules with the OS', () {
    test('a future reminder is scheduled, not shown, and is recorded', () async {
      final os = _RecordingService(scheduling: true);
      final dueAt = now.add(const Duration(hours: 2));
      await reminders.upsert(userId: 'u1', title: 'Call Sam', remindAt: dueAt);

      final scheduler = buildScheduler(using: os);
      await scheduler.start();

      expect(os.shown, isEmpty,
          reason: 'the OS owns future occurrences; showing here too would '
              'double up when it fires');
      expect(os.scheduled, hasLength(1));
      expect(os.scheduled.single.$1.title, 'Call Sam');
      expect(os.scheduled.single.$2.toUtc(), dueAt,
          reason: 'the database returns UTC instants in the device\'s own '
              'zone, so only the instant is part of the contract');
      expect(prefs.getString('delivered_notifications'), contains('reminder:'));
    });

    test('an already-due reminder is still shown immediately', () async {
      final os = _RecordingService(scheduling: true);
      await reminders.upsert(
        userId: 'u1',
        title: 'Now',
        remindAt: now.subtract(const Duration(minutes: 1)),
      );

      final scheduler = buildScheduler(using: os);
      await scheduler.start();

      expect(os.shown, hasLength(1));
      expect(os.scheduled, isEmpty);
    });

    test('future tasks are scheduled as one digest per slot', () async {
      final os = _RecordingService(scheduling: true);
      await tasks.upsert(
          userId: 'u1', title: 'Pay bill', dueDate: DateTime.utc(2026, 6, 16));
      await tasks.upsert(
          userId: 'u1',
          title: 'Send invoice',
          dueDate: DateTime.utc(2026, 6, 16));

      final scheduler = buildScheduler(using: os);
      await scheduler.start();

      expect(os.scheduled, hasLength(1),
          reason: 'a burst of notifications would bury the screen just as '
              'much on Android as on Windows');
      expect(os.scheduled.single.$1.title, '2 tasks due');
    });

    test('a refused schedule leaves the occurrence for the in-process fallback',
        () async {
      final os = _RecordingService(scheduling: true)..acceptSchedules = false;
      final dueAt = now.add(const Duration(hours: 1));
      await reminders.upsert(userId: 'u1', title: 'Later', remindAt: dueAt);

      final scheduler = buildScheduler(using: os);
      await scheduler.start();

      expect(os.scheduled, isEmpty);
      expect(prefs.getString('delivered_notifications') ?? '',
          isNot(contains('reminder:')),
          reason: 'recording it here would silence the fallback permanently');

      // The app stays alive past the time, so the in-process path still fires.
      now = dueAt.add(const Duration(minutes: 1));
      await scheduler.evaluate();
      expect(os.shown, hasLength(1));
    });

    test('deleting a scheduled reminder takes its OS notification back',
        () async {
      final os = _RecordingService(scheduling: true);
      await reminders.upsert(
        userId: 'u1',
        title: 'Call Sam',
        remindAt: now.add(const Duration(hours: 1)),
      );

      final scheduler = buildScheduler(using: os);
      await scheduler.start();
      expect(os.scheduled, hasLength(1));

      final id = (await reminders.watchActive().first).single.id;
      await reminders.softDelete(id);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await scheduler.evaluate();

      expect(os.cancelled, [Object.hash('reminder', id) & 0x7fffffff],
          reason: 'a deleted reminder must not still fire later');
    });
  });
}
