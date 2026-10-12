import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../recurrence/recurrence_engine.dart';
import '../time/app_timezone.dart';

/// Local-first CRUD for tasks. Every write stamps `updatedAt` and flags
/// `needsSync` so the sync engine can push it to Supabase.
class TaskRepository {
  TaskRepository(this._db);
  final AppDatabase _db;

  Stream<List<Task>> watchActive() => (_db.select(_db.tasks)
        ..where((t) => t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.asc(t.dueDate)]))
      .watch();

  Future<void> upsert({
    required String userId,
    String? id,
    required String title,
    String? notes,
    required DateTime dueDate, // UTC, date-only
    int priority = 1,
    String? recurrenceRule,
  }) async {
    final now = DateTime.now().toUtc();
    if (id == null) {
      await _db.into(_db.tasks).insert(TasksCompanion.insert(
            id: const Uuid().v4(),
            userId: userId,
            title: title,
            notes: Value(notes),
            dueDate: dueDate,
            priority: Value(priority),
            recurrenceRule: Value(recurrenceRule),
            createdAt: now,
            updatedAt: now,
          ));
    } else {
      await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
        TasksCompanion(
          title: Value(title),
          notes: Value(notes),
          dueDate: Value(dueDate),
          priority: Value(priority),
          recurrenceRule: Value(recurrenceRule),
          updatedAt: Value(now),
          needsSync: const Value(true),
        ),
      );
    }
  }

  /// Complete a task; recurring tasks roll forward to their next occurrence
  /// instead of being marked done.
  Future<void> toggleComplete(Task task) async {
    final now = DateTime.now().toUtc();
    final rule = task.recurrenceRule;
    if (rule != null && rule.isNotEmpty) {
      final next = RecurrenceEngine.nextAfter(
        startUtc: task.dueDate,
        rule: rule,
        afterUtc: now,
        location: AppTimezone.location,
      );
      await (_db.update(_db.tasks)..where((t) => t.id.equals(task.id))).write(
        TasksCompanion(
          dueDate: Value(next ?? now),
          updatedAt: Value(now),
          needsSync: const Value(true),
        ),
      );
    } else {
      final done = task.status != 'completed';
      await (_db.update(_db.tasks)..where((t) => t.id.equals(task.id))).write(
        TasksCompanion(
          status: Value(done ? 'completed' : 'pending'),
          completedAt: Value(done ? now : null),
          updatedAt: Value(now),
          needsSync: const Value(true),
        ),
      );
    }
  }

  Future<void> moveToToday(Task task) async {
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);
    await (_db.update(_db.tasks)..where((t) => t.id.equals(task.id))).write(
      TasksCompanion(
        dueDate: Value(today),
        status: const Value('pending'),
        completedAt: const Value(null),
        updatedAt: Value(now),
        needsSync: const Value(true),
      ),
    );
  }

  Future<void> softDelete(String id) async {
    final now = DateTime.now().toUtc();
    await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        needsSync: const Value(true),
      ),
    );
  }
}
