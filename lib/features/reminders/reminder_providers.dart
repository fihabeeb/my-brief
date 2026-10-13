import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/reminder_repository.dart';
import '../../core/data/reminder_timing.dart';
import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';

final reminderRepositoryProvider = Provider<ReminderRepository>(
    (ref) => ReminderRepository(ref.watch(appDatabaseProvider)));

final activeRemindersProvider = StreamProvider<List<Reminder>>(
    (ref) => ref.watch(reminderRepositoryProvider).watchActive());

class ReminderBoard {
  const ReminderBoard({
    required this.overdue,
    required this.next24h,
    required this.later,
    required this.completed,
  });

  final List<Reminder> overdue;
  final List<Reminder> next24h;
  final List<Reminder> later;
  final List<Reminder> completed;

  int get activeCount => overdue.length + next24h.length + later.length;
}

/// Effective fire instant (a snoozed reminder fires at `snoozedUntil`).
///
/// Delegates to the shared rule in `reminder_timing.dart` so the dashboard can
/// never disagree with what the notification scheduler actually fires.
DateTime effectiveFire(Reminder r) =>
    effectiveFireAt(remindAt: r.remindAt, snoozedUntil: r.snoozedUntil);

final reminderBoardProvider = Provider<ReminderBoard>((ref) {
  final reminders =
      ref.watch(activeRemindersProvider).value ?? const <Reminder>[];
  final now = DateTime.now().toUtc();
  final horizon = now.add(const Duration(hours: 24));

  final overdue = <Reminder>[];
  final next24h = <Reminder>[];
  final later = <Reminder>[];
  final completed = <Reminder>[];

  for (final r in reminders) {
    if (r.status == 'completed') {
      completed.add(r);
      continue;
    }
    final fire = effectiveFire(r);
    if (fire.isBefore(now)) {
      overdue.add(r);
    } else if (!fire.isAfter(horizon)) {
      next24h.add(r);
    } else {
      later.add(r);
    }
  }

  return ReminderBoard(
    overdue: overdue,
    next24h: next24h,
    later: later,
    completed: completed,
  );
});
