import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/recurrence/recurrence_engine.dart';
import '../../core/supabase/supabase_service.dart';
import '../../core/utils/format.dart';
import 'reminder_providers.dart';

enum ReminderRecurrenceOption { none, daily, weekly, monthly }

String _ruleFromOption(ReminderRecurrenceOption o) => switch (o) {
      ReminderRecurrenceOption.none => '',
      ReminderRecurrenceOption.daily => RecurrenceEngine.daily(),
      ReminderRecurrenceOption.weekly => 'RRULE:FREQ=WEEKLY',
      ReminderRecurrenceOption.monthly => RecurrenceEngine.monthly(),
    };

ReminderRecurrenceOption _optionFromRule(String? rule) {
  final r = (rule ?? '').toUpperCase();
  if (r.isEmpty) return ReminderRecurrenceOption.none;
  if (r.contains('FREQ=DAILY')) return ReminderRecurrenceOption.daily;
  if (r.contains('FREQ=WEEKLY')) return ReminderRecurrenceOption.weekly;
  if (r.contains('FREQ=MONTHLY')) return ReminderRecurrenceOption.monthly;
  return ReminderRecurrenceOption.none;
}

class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(reminderBoardProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDialog(
            context: context, builder: (_) => const ReminderEditorDialog()),
        icon: const Icon(Icons.add),
        label: const Text('New reminder'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (board.overdue.isNotEmpty)
            _SectionHeader('Overdue', board.overdue.length, Colors.red),
          ...board.overdue.map((r) => _ReminderTile(reminder: r)),
          if (board.next24h.isNotEmpty)
            _SectionHeader('Next 24 hours', board.next24h.length, Colors.orange),
          ...board.next24h.map((r) => _ReminderTile(reminder: r)),
          if (board.later.isNotEmpty)
            _SectionHeader('Later', board.later.length, Colors.blue),
          ...board.later.map((r) => _ReminderTile(reminder: r)),
          if (board.completed.isNotEmpty)
            _SectionHeader('Completed', board.completed.length, Colors.green),
          ...board.completed.map((r) => _ReminderTile(reminder: r)),
          if (board.activeCount == 0 && board.completed.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                  child: Text('No reminders yet. Tap "New reminder".')),
            ),
        ],
      ),
    );
  }
}

class _ReminderTile extends ConsumerWidget {
  const _ReminderTile({required this.reminder});
  final Reminder reminder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final done = reminder.status == 'completed';
    final repo = ref.read(reminderRepositoryProvider);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Checkbox(
          value: done,
          shape: const CircleBorder(),
          onChanged: (_) => repo.toggleComplete(reminder),
        ),
        title: Text(
          reminder.title,
          style: TextStyle(
            decoration: done ? TextDecoration.lineThrough : null,
            color: done ? Theme.of(context).colorScheme.outline : null,
          ),
        ),
        subtitle: Text(
          [
            fmtDateTime(effectiveFire(reminder)),
            if (reminder.snoozedUntil != null) 'snoozed',
            if (reminder.recurrenceRule != null &&
                reminder.recurrenceRule!.isNotEmpty)
              'Repeats',
          ].join(' · '),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'edit') {
              await showDialog(
                  context: context,
                  builder: (_) => ReminderEditorDialog(reminder: reminder));
            } else if (v == 's10') {
              await repo.snooze(reminder, const Duration(minutes: 10));
            } else if (v == 's60') {
              await repo.snooze(reminder, const Duration(hours: 1));
            } else if (v == 'done') {
              await repo.toggleComplete(reminder);
            } else if (v == 'delete') {
              await repo.softDelete(reminder.id);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            if (!done) ...[
              const PopupMenuItem(
                  value: 's10', child: Text('Snooze 10 minutes')),
              const PopupMenuItem(value: 's60', child: Text('Snooze 1 hour')),
              const PopupMenuItem(value: 'done', child: Text('Mark done')),
            ],
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
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

class ReminderEditorDialog extends ConsumerStatefulWidget {
  const ReminderEditorDialog({super.key, this.reminder});
  final Reminder? reminder;

  @override
  ConsumerState<ReminderEditorDialog> createState() =>
      _ReminderEditorDialogState();
}

class _ReminderEditorDialogState extends ConsumerState<ReminderEditorDialog> {
  late final TextEditingController _title =
      TextEditingController(text: widget.reminder?.title ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.reminder?.notes ?? '');
  late DateTime _date;
  late TimeOfDay _time;
  late ReminderRecurrenceOption _recurrence;

  @override
  void initState() {
    super.initState();
    final r = widget.reminder;
    if (r != null) {
      final l = r.remindAt.toLocal();
      _date = DateTime(l.year, l.month, l.day);
      _time = TimeOfDay(hour: l.hour, minute: l.minute);
      _recurrence = _optionFromRule(r.recurrenceRule);
    } else {
      final n = DateTime.now().add(const Duration(hours: 1));
      _date = DateTime(n.year, n.month, n.day);
      _time = TimeOfDay(hour: n.hour, minute: n.minute);
      _recurrence = ReminderRecurrenceOption.none;
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
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _date = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final local = DateTime(
        _date.year, _date.month, _date.day, _time.hour, _time.minute);
    await ref.read(reminderRepositoryProvider).upsert(
          userId: SupabaseService.currentUserId,
          id: widget.reminder?.id,
          title: title,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          remindAt: local.toUtc(),
          recurrenceRule: _recurrence == ReminderRecurrenceOption.none
              ? null
              : _ruleFromOption(_recurrence),
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.reminder == null ? 'New reminder' : 'Edit reminder'),
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
                    label: Text(fmtDay(DateTime.utc(
                        _date.year, _date.month, _date.day))),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.access_time, size: 16),
                    label: Text(_time.format(context)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ReminderRecurrenceOption>(
              initialValue: _recurrence,
              decoration: const InputDecoration(labelText: 'Repeat'),
              items: const [
                DropdownMenuItem(
                    value: ReminderRecurrenceOption.none, child: Text('Never')),
                DropdownMenuItem(
                    value: ReminderRecurrenceOption.daily,
                    child: Text('Daily')),
                DropdownMenuItem(
                    value: ReminderRecurrenceOption.weekly,
                    child: Text('Weekly')),
                DropdownMenuItem(
                    value: ReminderRecurrenceOption.monthly,
                    child: Text('Monthly')),
              ],
              onChanged: (v) => setState(
                  () => _recurrence = v ?? ReminderRecurrenceOption.none),
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
