import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/task_repository.dart';
import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';

final taskRepositoryProvider = Provider<TaskRepository>(
    (ref) => TaskRepository(ref.watch(appDatabaseProvider)));

final activeTasksProvider = StreamProvider<List<Task>>(
    (ref) => ref.watch(taskRepositoryProvider).watchActive());

class TaskBoard {
  const TaskBoard({
    required this.overdue,
    required this.today,
    required this.upcoming,
    required this.completed,
  });

  final List<Task> overdue;
  final List<Task> today;
  final List<Task> upcoming;
  final List<Task> completed;

  int get openCount => overdue.length + today.length;
}

final taskBoardProvider = Provider<TaskBoard>((ref) {
  final tasks = ref.watch(activeTasksProvider).value ?? const <Task>[];
  final now = DateTime.now().toUtc();
  final today = DateTime.utc(now.year, now.month, now.day);
  final tomorrow = today.add(const Duration(days: 1));

  final overdue = <Task>[];
  final todayList = <Task>[];
  final upcoming = <Task>[];
  final completed = <Task>[];

  for (final t in tasks) {
    if (t.status == 'completed') {
      completed.add(t);
    } else if (t.dueDate.isBefore(today)) {
      overdue.add(t);
    } else if (t.dueDate.isBefore(tomorrow)) {
      todayList.add(t);
    } else {
      upcoming.add(t);
    }
  }
  completed.sort((a, b) => (b.completedAt ?? b.updatedAt)
      .compareTo(a.completedAt ?? a.updatedAt));

  return TaskBoard(
    overdue: overdue,
    today: todayList,
    upcoming: upcoming,
    completed: completed,
  );
});
