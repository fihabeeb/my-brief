import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;

import '../data/reminder_timing.dart';
import 'notification_intent.dart';

/// Which side of the app a plan came from.
enum PlannedKind { reminder, task }

/// A reminder reduced to the fields the planner needs. Kept independent of Drift
/// so the planner can be unit-tested without a database.
@immutable
class ReminderInput {
  const ReminderInput({
    required this.id,
    required this.title,
    required this.remindAt,
    required this.status,
    this.notes,
    this.snoozedUntil,
  });

  final String id;
  final String title;
  final String? notes;

  /// Anchor instant (UTC). Recurring reminders roll this forward when completed.
  final DateTime remindAt;
  final String status;
  final DateTime? snoozedUntil;

  bool get isCompleted => status == 'completed';

  DateTime get fireAt =>
      effectiveFireAt(remindAt: remindAt, snoozedUntil: snoozedUntil);
}

/// A task reduced to the fields the planner needs.
@immutable
class TaskInput {
  const TaskInput({
    required this.id,
    required this.title,
    required this.dueDate,
    required this.status,
    this.notes,
  });

  final String id;
  final String title;
  final String? notes;

  /// Calendar date (UTC, date-only) the task is due.
  final DateTime dueDate;
  final String status;

  bool get isCompleted => status == 'completed';
}

/// One notification the scheduler should produce.
@immutable
class PlannedNotification {
  const PlannedNotification({
    required this.kind,
    required this.itemId,
    required this.occurrenceKey,
    required this.fireAt,
    required this.title,
    required this.body,
    required this.onOpen,
    this.actions = const [],
  });

  final PlannedKind kind;
  final String itemId;

  /// Stable id for *this occurrence* of *this item*. Persisted once notified so
  /// the same occurrence is never announced twice — across restarts, and
  /// without relying on `cancel()`, which is a no-op on unpackaged Windows.
  final String occurrenceKey;

  /// UTC instant at which this should be announced.
  final DateTime fireAt;

  final String title;
  final String body;
  final NotificationIntent onOpen;
  final List<NotificationAction> actions;
}

/// Pure, testable decision logic: *what* to announce and *when*.
///
/// Contains no I/O, no timers and no Flutter — the scheduler supplies data and
/// a clock, and is responsible for firing and for persisting [PlannedNotification.occurrenceKey].
class DuePlanner {
  const DuePlanner({
    required this.location,
    required this.taskNotifyHour,
    required this.snoozeMinutes,
  });

  /// Device timezone, used to turn a task's calendar date into a wall-clock hour.
  final tz.Location location;

  /// Local hour (0-23) at which due tasks are announced.
  final int taskNotifyHour;

  /// Snooze length offered on a reminder toast.
  final int snoozeMinutes;

  /// Every notification worth planning, ascending by [PlannedNotification.fireAt].
  ///
  /// Includes both already-due items (`fireAt <= now`, fire immediately) and
  /// future ones (arm a timer), minus occurrences already in [delivered].
  List<PlannedNotification> plan({
    required List<ReminderInput> reminders,
    required List<TaskInput> tasks,
    required DateTime now,
    required Set<String> delivered,
  }) {
    final out = <PlannedNotification>[];

    for (final r in reminders) {
      if (r.isCompleted) continue;
      final fireAt = r.fireAt;
      final key = _key('reminder', r.id, fireAt);
      if (delivered.contains(key)) continue;
      out.add(PlannedNotification(
        kind: PlannedKind.reminder,
        itemId: r.id,
        occurrenceKey: key,
        fireAt: fireAt,
        title: r.title,
        body: (r.notes != null && r.notes!.isNotEmpty)
            ? r.notes!
            : 'Reminder due now',
        onOpen: const NavIntent('/reminders'),
        actions: [
          NotificationAction(
            label: 'Snooze ${snoozeMinutes}m',
            intent: SnoozeIntent(r.id, snoozeMinutes),
          ),
          NotificationAction(label: 'Done', intent: DoneIntent(r.id)),
        ],
      ));
    }

    for (final t in tasks) {
      if (t.isCompleted) continue;
      final fireAt = _taskFireAt(t.dueDate, now);
      final key = _key('task', t.id, t.dueDate);
      if (delivered.contains(key)) continue;
      out.add(PlannedNotification(
        kind: PlannedKind.task,
        itemId: t.id,
        occurrenceKey: key,
        fireAt: fireAt,
        title: t.title,
        body: (t.notes != null && t.notes!.isNotEmpty)
            ? t.notes!
            : 'Task due today',
        onOpen: const NavIntent('/tasks'),
      ));
    }

    out.sort((a, b) => a.fireAt.compareTo(b.fireAt));
    return out;
  }

  /// Announce a task at [taskNotifyHour] on its due date.
  ///
  /// Tasks store a calendar date with no time, so this is what gives them an
  /// hour. Overdue tasks wait for the *next* announcement slot instead of
  /// firing at whatever time the app happens to open — they never fire in the
  /// middle of the night, and each due date is still announced exactly once.
  DateTime _taskFireAt(DateTime dueDate, DateTime now) {
    final nowLocal = tz.TZDateTime.from(now, location);
    final today = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);

    // `dueDate` is written as UTC midnight, but the database hands it back in
    // the device's own zone. Reading the date straight off that value would
    // use the local calendar day, so a machine west of UTC — where UTC
    // midnight has already rolled back into the previous day — would see a
    // task as due a day early. Both sides are built as naive dates below so
    // the comparison is a pure calendar one.
    final dueUtc = dueDate.toUtc();
    final due = DateTime(dueUtc.year, dueUtc.month, dueUtc.day);

    final target = due.isBefore(today) ? today : due;
    return tz.TZDateTime(
      location,
      target.year,
      target.month,
      target.day,
      taskNotifyHour,
    ).toUtc();
  }

  String _key(String kind, String id, DateTime occurrence) =>
      '$kind:$id:${occurrence.millisecondsSinceEpoch}';
}
