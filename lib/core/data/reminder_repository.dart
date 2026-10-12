import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../recurrence/recurrence_engine.dart';
import '../time/app_timezone.dart';

/// Local-first CRUD for reminders. Timestamps are stored in UTC.
class ReminderRepository {
  ReminderRepository(this._db);
  final AppDatabase _db;

  Stream<List<Reminder>> watchActive() => (_db.select(_db.reminders)
        ..where((r) => r.deletedAt.isNull())
        ..orderBy([(r) => OrderingTerm.asc(r.remindAt)]))
      .watch();

  Future<void> upsert({
    required String userId,
    String? id,
    required String title,
    String? notes,
    required DateTime remindAt, // UTC
    String? recurrenceRule,
  }) async {
    final now = DateTime.now().toUtc();
    if (id == null) {
      await _db.into(_db.reminders).insert(RemindersCompanion.insert(
            id: const Uuid().v4(),
            userId: userId,
            title: title,
            notes: Value(notes),
            remindAt: remindAt,
            recurrenceRule: Value(recurrenceRule),
            createdAt: now,
            updatedAt: now,
          ));
    } else {
      await (_db.update(_db.reminders)..where((r) => r.id.equals(id))).write(
        RemindersCompanion(
          title: Value(title),
          notes: Value(notes),
          remindAt: Value(remindAt),
          recurrenceRule: Value(recurrenceRule),
          updatedAt: Value(now),
          needsSync: const Value(true),
        ),
      );
    }
  }

  Future<void> toggleComplete(Reminder reminder) async {
    final now = DateTime.now().toUtc();
    final rule = reminder.recurrenceRule;
    if (rule != null && rule.isNotEmpty) {
      final next = RecurrenceEngine.nextAfter(
        startUtc: reminder.remindAt,
        rule: rule,
        afterUtc: now,
        location: AppTimezone.location,
      );
      await (_db.update(_db.reminders)..where((r) => r.id.equals(reminder.id)))
          .write(RemindersCompanion(
        remindAt: Value(next ?? now),
        snoozedUntil: const Value(null),
        updatedAt: Value(now),
        needsSync: const Value(true),
      ));
    } else {
      final done = reminder.status != 'completed';
      await (_db.update(_db.reminders)..where((r) => r.id.equals(reminder.id)))
          .write(RemindersCompanion(
        status: Value(done ? 'completed' : 'upcoming'),
        completedAt: Value(done ? now : null),
        snoozedUntil: const Value(null),
        updatedAt: Value(now),
        needsSync: const Value(true),
      ));
    }
  }

  Future<void> snooze(Reminder reminder, Duration by) async {
    final now = DateTime.now().toUtc();
    await (_db.update(_db.reminders)..where((r) => r.id.equals(reminder.id)))
        .write(RemindersCompanion(
      snoozedUntil: Value(now.add(by)),
      updatedAt: Value(now),
      needsSync: const Value(true),
    ));
  }

  Future<void> softDelete(String id) async {
    final now = DateTime.now().toUtc();
    await (_db.update(_db.reminders)..where((r) => r.id.equals(id))).write(
      RemindersCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        needsSync: const Value(true),
      ),
    );
  }
}
