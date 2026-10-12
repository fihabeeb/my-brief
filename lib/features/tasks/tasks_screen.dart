import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/recurrence/recurrence_engine.dart';
import '../../core/supabase/supabase_service.dart';
import '../../core/utils/format.dart';
import 'task_providers.dart';

enum TaskRecurrenceOption { none, daily, weekdays, weekly, monthly }

String _ruleFromOption(TaskRecurrenceOption o) => switch (o) {
      TaskRecurrenceOption.none => '',
      TaskRecurrenceOption.daily => RecurrenceEngine.daily(),
      TaskRecurrenceOption.weekdays => RecurrenceEngine.weekdays(),
      TaskRecurrenceOption.weekly => 'RRULE:FREQ=WEEKLY',
      TaskRecurrenceOption.monthly => RecurrenceEngine.monthly(),
    };

TaskRecurrenceOption _optionFromRule(String? rule) {
  final r = (rule ?? '').toUpperCase();
  if (r.isEmpty) return TaskRecurrenceOption.none;
  if (r.contains('BYDAY=MO,TU,WE,TH,FR')) return TaskRecurrenceOption.weekdays;
  if (r.contains('FREQ=DAILY')) return TaskRecurrenceOption.daily;
  if (r.contains('FREQ=WEEKLY')) return TaskRecurrenceOption.weekly;
  if (r.contains('FREQ=MONTHLY')) return TaskRecurrenceOption.monthly;
  return TaskRecurrenceOption.none;
}

class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(taskBoardProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Tasks')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('New task'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (board.overdue.isNotEmpty)
            _SectionHeader('Overdue', board.overdue.length, Colors.red),
          ...board.overdue.map((t) => _TaskTile(task: t)),
          _SectionHeader('Today', board.today.length, Colors.orange),
          ...board.today.map((t) => _TaskTile(task: t)),
          if (board.upcoming.isNotEmpty)
            _SectionHeader('Upcoming', board.upcoming.length, Colors.blue),
          ...board.upcoming.map((t) => _TaskTile(task: t)),
          if (board.completed.isNotEmpty)
            _SectionHeader('Completed', board.completed.length, Colors.green),
          ...board.completed.map((t) => _TaskTile(task: t)),
          if (board.openCount == 0 && board.completed.isEmpty)
            const _EmptyState('No tasks yet. Tap "New task" to add one.'),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Task? task) {
    return showDialog(
      context: context,
      builder: (_) => TaskEditorDialog(task: task),
    );
  }
}

class _TaskTile extends ConsumerWidget {
  const _TaskTile({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final done = task.status == 'completed';
    final repo = ref.read(taskRepositoryProvider);
    final color = switch (task.priority) {
      2 => Colors.red,
      0 => Colors.grey,
      _ => Colors.blueGrey,
    };

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Checkbox(
          value: done,
          shape: const CircleBorder(),
          onChanged: (_) => repo.toggleComplete(task),
        ),
        title: Text(
          task.title,
          style: TextStyle(
            decoration: done ? TextDecoration.lineThrough : null,
            color: done ? Theme.of(context).colorScheme.outline : null,
          ),
        ),
        subtitle: Text(
          [
            fmtDay(task.dueDate),
            if (task.recurrenceRule != null &&
                task.recurrenceRule!.isNotEmpty)
              'Repeats',
          ].join(' · '),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'edit') {
                  await showDialog(
                      context: context,
                      builder: (_) => TaskEditorDialog(task: task));
                } else if (v == 'today') {
                  await repo.moveToToday(task);
                } else if (v == 'delete') {
                  await repo.softDelete(task.id);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                if (!done)
                  const PopupMenuItem(
                      value: 'today', child: Text('Move to today')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label, this.count, this.color);
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(width: 8),
          Text('$count', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(child: Text(message)),
    );
  }
}

class TaskEditorDialog extends ConsumerStatefulWidget {
  const TaskEditorDialog({super.key, this.task});
  final Task? task;

  @override
  ConsumerState<TaskEditorDialog> createState() => _TaskEditorDialogState();
}

class _TaskEditorDialogState extends ConsumerState<TaskEditorDialog> {
  late final TextEditingController _title =
      TextEditingController(text: widget.task?.title ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.task?.notes ?? '');
  late DateTime _dueDate;
  late int _priority;
  late TaskRecurrenceOption _recurrence;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    if (t != null) {
      final l = t.dueDate.toLocal();
      _dueDate = DateTime(l.year, l.month, l.day);
      _priority = t.priority;
      _recurrence = _optionFromRule(t.recurrenceRule);
    } else {
      final n = DateTime.now();
      _dueDate = DateTime(n.year, n.month, n.day);
      _priority = 1;
      _recurrence = TaskRecurrenceOption.none;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _dueDate = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final repo = ref.read(taskRepositoryProvider);
    await repo.upsert(
      userId: SupabaseService.currentUserId,
      id: widget.task?.id,
      title: title,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      dueDate: DateTime.utc(_dueDate.year, _dueDate.month, _dueDate.day),
      priority: _priority,
      recurrenceRule: _recurrence == TaskRecurrenceOption.none
          ? null
          : _ruleFromOption(_recurrence),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.task == null ? 'New task' : 'Edit task'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(fmtDay(
                        DateTime.utc(_dueDate.year, _dueDate.month, _dueDate.day))),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _priority,
              decoration: const InputDecoration(labelText: 'Priority'),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Low')),
                DropdownMenuItem(value: 1, child: Text('Normal')),
                DropdownMenuItem(value: 2, child: Text('High')),
              ],
              onChanged: (v) => setState(() => _priority = v ?? 1),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<TaskRecurrenceOption>(
              initialValue: _recurrence,
              decoration: const InputDecoration(labelText: 'Repeat'),
              items: const [
                DropdownMenuItem(
                    value: TaskRecurrenceOption.none, child: Text('Never')),
                DropdownMenuItem(
                    value: TaskRecurrenceOption.daily, child: Text('Daily')),
                DropdownMenuItem(
                    value: TaskRecurrenceOption.weekdays,
                    child: Text('Weekdays')),
                DropdownMenuItem(
                    value: TaskRecurrenceOption.weekly, child: Text('Weekly')),
                DropdownMenuItem(
                    value: TaskRecurrenceOption.monthly,
                    child: Text('Monthly')),
              ],
              onChanged: (v) =>
                  setState(() => _recurrence = v ?? TaskRecurrenceOption.none),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
