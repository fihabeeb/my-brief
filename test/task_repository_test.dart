import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mybrief/core/data/task_repository.dart';
import 'package:mybrief/core/data/reminder_repository.dart';
import 'package:mybrief/core/database/app_database.dart';
import 'package:mybrief/core/recurrence/recurrence_engine.dart';

void main() {
  late AppDatabase db;
  late TaskRepository tasks;
  late ReminderRepository reminders;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tasks = TaskRepository(db);
    reminders = ReminderRepository(db);
  });

  tearDown(() => db.close());

  group('TaskRepository', () {
    test('create, list, complete, soft delete', () async {
      await tasks.upsert(
        userId: 'u1',
        title: 'Buy milk',
        dueDate: DateTime.utc(2024, 1, 1),
      );

      var list = await tasks.watchActive().first;
      expect(list, hasLength(1));

      await tasks.toggleComplete(list.first);
      list = await tasks.watchActive().first;
      expect(list.first.status, 'completed');
      expect(list.first.completedAt, isNotNull);

      await tasks.softDelete(list.first.id);
      list = await tasks.watchActive().first;
      expect(list, isEmpty);
    });

    test('completing a recurring task advances its due date', () async {
      final start = DateTime.utc(2024, 1, 1);
      await tasks.upsert(
        userId: 'u1',
        title: 'Daily water plants',
        dueDate: start,
        recurrenceRule: RecurrenceEngine.daily(),
      );

      final list = await tasks.watchActive().first;
      await tasks.toggleComplete(list.first);

      final after = await tasks.watchActive().first;
      expect(after.first.dueDate.isAfter(DateTime.utc(2024, 1, 1)), isTrue,
          reason: 'recurring task should roll forward, not complete');
      expect(after.first.status, 'pending');
    });
  });

  group('ReminderRepository', () {
    test('create, snooze, complete', () async {
      await reminders.upsert(
        userId: 'u1',
        title: 'Call Sam',
        remindAt: DateTime.utc(2024, 1, 1, 15),
      );

      var list = await reminders.watchActive().first;
      await reminders.snooze(list.first, const Duration(minutes: 10));
      list = await reminders.watchActive().first;
      expect(list.first.snoozedUntil, isNotNull);

      await reminders.toggleComplete(list.first);
      list = await reminders.watchActive().first;
      expect(list.first.status, 'completed');
    });
  });
}
