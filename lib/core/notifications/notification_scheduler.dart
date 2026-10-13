import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/reminder_repository.dart';
import '../data/task_repository.dart';
import '../database/app_database.dart';
import '../utils/logger.dart';
import 'due_planner.dart';
import 'notification_intent.dart';
import 'notification_service.dart';

/// Turns due reminders and tasks into toast notifications.
///
/// Windows has no scheduling API, so this runs in-process: it watches the local
/// database, asks a [DuePlanner] what is due, shows what is due *now*, and arms
/// a timer for the next occurrence. Every announced occurrence is recorded in
/// SharedPreferences, which is what stops the same reminder firing twice —
/// `cancel()` cannot, because it is a no-op on unpackaged Windows.
class NotificationScheduler {
  NotificationScheduler({
    required this.service,
    required this.reminders,
    required this.tasks,
    required this.prefs,
    required this.planner,
    required this.onNavigate,
    required this.onActivate,
    this.clock = DateTime.now,
  });

  static const _deliveredKey = 'delivered_notifications';
  static const _maxDelivered = 500;
  static const _maxBodyLines = 5;

  final NotificationService service;
  final ReminderRepository reminders;
  final TaskRepository tasks;
  final SharedPreferences prefs;
  final DuePlanner planner;

  /// Bring the app window to the front (toast clicked while hidden in tray).
  final Future<void> Function() onActivate;
  final void Function(String route) onNavigate;
  final DateTime Function() clock;

  StreamSubscription<List<Reminder>>? _reminderSub;
  StreamSubscription<List<Task>>? _taskSub;
  Timer? _timer;

  /// Serializes evaluations (see [evaluate]).
  Future<void> _queue = Future<void>.value();

  List<Reminder> _reminderRows = const [];
  List<Task> _taskRows = const [];

  // Guards pruning until each stream has delivered at least once — otherwise a
  // cold start would see "no items" and wrongly forget every delivered key.
  bool _remindersReady = false;
  bool _tasksReady = false;

  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    final remindersReady = Completer<void>();
    _reminderSub = reminders.watchActive().listen((rows) {
      _reminderRows = rows;
      _remindersReady = true;
      if (!remindersReady.isCompleted) remindersReady.complete();
      evaluate();
    });

    final tasksReady = Completer<void>();
    _taskSub = tasks.watchActive().listen((rows) {
      _taskRows = rows;
      _tasksReady = true;
      if (!tasksReady.isCompleted) tasksReady.complete();
      evaluate();
    });

    // Wait for the first snapshot so the opening evaluate sees real rows rather
    // than the empty pre-emission state — but never block startup on it.
    await Future.wait([remindersReady.future, tasksReady.future]).timeout(
      const Duration(seconds: 5),
      onTimeout: () => <void>[],
    );

    await evaluate();
  }

  void stop() {
    _started = false;
    _timer?.cancel();
    _timer = null;
    _reminderSub?.cancel();
    _reminderSub = null;
    _taskSub?.cancel();
    _taskSub = null;
  }

  /// Recomputes what is due, shows it, records it, and re-arms the timer.
  ///
  /// Calls are **serialized**: the two database streams often emit back to
  /// back, and if those evaluations overlapped they would both read the same
  /// "delivered" set and announce an occurrence twice. Returns a future that
  /// completes once the queued pass (and any earlier ones) has finished.
  Future<void> evaluate() {
    final next = _queue.then((_) async {
      if (!_started) return;
      await _evaluateOnce();
    });
    _queue = next;
    return next;
  }

  Future<void> _evaluateOnce() async {
    try {
      final now = clock();
      final delivered = _loadDelivered();
      final originalCount = delivered.length;

      final plans = planner.plan(
        reminders: [for (final r in _reminderRows) _reminderInput(r)],
        tasks: [for (final t in _taskRows) _taskInput(t)],
        now: now,
        delivered: delivered,
      );

      final due = [for (final p in plans) if (!p.fireAt.isAfter(now)) p];
      final upcoming = [for (final p in plans) if (p.fireAt.isAfter(now)) p];

      if (due.isNotEmpty) {
        final fired = await _fire(due);
        delivered.addAll(fired);
      }

      // Persist when something new fired *or* when pruning dropped a key for
      // an item the user deleted — otherwise a deleted reminder's key would
      // linger until the next unrelated notification.
      final pruned = _prune(delivered);
      if (delivered.length != originalCount || pruned.length != delivered.length) {
        await _persistDelivered(pruned);
      }

      _arm(upcoming);
    } catch (e) {
      log.warning('Notification evaluate failed: $e');
    }
  }

  /// Handles a toast interaction: navigation or a snooze/done action.
  Future<void> handleIntent(NotificationIntent intent) async {
    switch (intent) {
      case OpenAppIntent():
        await onActivate();
      case NavIntent():
        await onActivate();
        onNavigate(intent.route);
      case SnoozeIntent():
        await onActivate();
        final row = await reminders.byId(intent.reminderId);
        if (row != null) {
          await reminders.snooze(row, Duration(minutes: intent.minutes));
        }
      case DoneIntent():
        await onActivate();
        final row = await reminders.byId(intent.reminderId);
        if (row != null) await reminders.toggleComplete(row);
    }
  }

  // ---- firing ----

  Future<Set<String>> _fire(List<PlannedNotification> due) async {
    final fired = <String>{};
    final taskDue = [for (final p in due) if (p.kind == PlannedKind.task) p];
    final reminderDue = [
      for (final p in due) if (p.kind == PlannedKind.reminder) p
    ];

    // All tasks in this pass become one toast, so five due tasks don't bury
    // the screen. Reminders stay separate because each carries its own
    // snooze/done buttons.
    if (taskDue.isNotEmpty) {
      try {
        await service.show(_groupedTaskRequest(taskDue));
        fired.addAll(taskDue.map((p) => p.occurrenceKey));
      } catch (e) {
        log.warning('Task notification failed: $e');
      }
    }

    for (final p in reminderDue) {
      try {
        await service.show(NotificationRequest(
          id: _idFor(p.kind, p.itemId),
          title: p.title,
          body: p.body,
          payload: p.onOpen.encode(),
          actions: p.actions,
        ));
        fired.add(p.occurrenceKey);
      } catch (e) {
        log.warning('Reminder notification failed: $e');
      }
    }
    return fired;
  }

  NotificationRequest _groupedTaskRequest(List<PlannedNotification> taskDue) {
    final titles = [for (final p in taskDue) p.title];
    final shown = titles.take(_maxBodyLines);
    final overflow = titles.length - shown.length;
    final count = taskDue.length;
    return NotificationRequest(
      id: _idFor(PlannedKind.task, '*group*'),
      title: count == 1 ? '1 task due' : '$count tasks due',
      body: [
        ...shown,
        if (overflow > 0) '+$overflow more',
      ].join('\n'),
      payload: const NavIntent('/tasks').encode(),
    );
  }

  int _idFor(PlannedKind kind, String itemId) =>
      Object.hash(kind.name, itemId) & 0x7fffffff;

  // ---- timers ----

  void _arm(List<PlannedNotification> upcoming) {
    _timer?.cancel();
    _timer = null;
    if (!_started || upcoming.isEmpty) return;
    // plan() sorts ascending, so this is the next thing worth announcing.
    final delay = upcoming.first.fireAt.difference(clock());
    _timer = Timer(delay.isNegative ? Duration.zero : delay, evaluate);
  }

  // ---- delivered-occurrence store ----

  Set<String> _loadDelivered() {
    final raw = prefs.getString(_deliveredKey);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.whereType<String>().toSet();
    } catch (_) {
      // Corrupt value: start clean rather than throwing on every evaluate.
    }
    return <String>{};
  }

  Future<void> _persistDelivered(Set<String> keys) =>
      prefs.setString(_deliveredKey, jsonEncode(keys.toList()));

  /// Forgets keys for items the user has deleted (so the set can't grow
  /// forever) and caps the size. Keys for an item that still exists are always
  /// kept, however old — that is what stops an overdue task re-firing.
  Set<String> _prune(Set<String> keys) {
    final reminderIds = _remindersReady
        ? _reminderRows.map((r) => r.id).toSet()
        : null;
    final taskIds = _tasksReady ? _taskRows.map((t) => t.id).toSet() : null;

    final kept = <String>[];
    for (final key in keys) {
      final split = _splitKey(key);
      if (split == null) continue; // malformed -> drop

      final (kind, id) = split;
      final live = switch (kind) {
        'reminder' => reminderIds?.contains(id) ?? true,
        'task' => taskIds?.contains(id) ?? true,
        _ => false,
      };
      if (live) kept.add(key);
    }

    if (kept.length > _maxDelivered) {
      kept.sort((a, b) => _occurrenceOf(b).compareTo(_occurrenceOf(a)));
      kept.length = _maxDelivered;
    }
    return kept.toSet();
  }

  /// `kind:id:millis` -> (kind, id), or null if malformed.
  (String, String)? _splitKey(String key) {
    final first = key.indexOf(':');
    if (first <= 0) return null;
    final second = key.indexOf(':', first + 1);
    if (second <= first + 1) return null;
    return (key.substring(0, first), key.substring(first + 1, second));
  }

  int _occurrenceOf(String key) {
    final last = key.lastIndexOf(':');
    return last < 0 ? 0 : int.tryParse(key.substring(last + 1)) ?? 0;
  }

  // ---- row mapping ----

  ReminderInput _reminderInput(Reminder r) => ReminderInput(
        id: r.id,
        title: r.title,
        notes: r.notes,
        remindAt: r.remindAt,
        status: r.status,
        snoozedUntil: r.snoozedUntil,
      );

  TaskInput _taskInput(Task t) => TaskInput(
        id: t.id,
        title: t.title,
        notes: t.notes,
        dueDate: t.dueDate,
        status: t.status,
      );
}
