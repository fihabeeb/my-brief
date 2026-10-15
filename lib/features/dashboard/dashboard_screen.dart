import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/database/app_database.dart';
import '../../core/sync/sync_service.dart';
import '../../core/utils/format.dart';
import '../inbox/inbox_providers.dart';
import '../reminders/reminder_providers.dart';
import '../tasks/task_providers.dart';
import 'dashboard_providers.dart';

/// First screen after sign-in: what is happening today, and how much of it is
/// left.
///
/// The list is local-first (Drift streams), so it is always current on its own.
/// Pull-to-refresh and the refresh action in the app bar drive **sync** — the
/// round trip to Supabase — rather than re-reading the database. On Windows a
/// mouse cannot pull to refresh, so the app-bar button is the reliable path
/// there and the refresh indicator is a bonus on Android.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  Future<void> _sync(WidgetRef ref) => ref.read(syncServiceProvider).syncNow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskBoard = ref.watch(taskBoardProvider);
    final reminderBoard = ref.watch(reminderBoardProvider);

    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 18
            ? 'Good afternoon'
            : 'Good evening';
    final name = ref.watch(greetingNameProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Brief'),
        actions: [
          IconButton(
            tooltip: 'Sync now',
            icon: const Icon(Icons.sync),
            onPressed: () => _sync(ref),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Material 3's medium breakpoint: two columns when there is genuinely
          // room for them, rather than always stacking and wasting a desktop
          // window.
          final wide = constraints.maxWidth >= 840;

          final header = _Greeting(
            greeting: name == null ? greeting : '$greeting, $name',
            date: DateFormat('EEEE, d MMMM yyyy').format(now),
          );
          final today = _TodayTasksCard(
            tasks: [...taskBoard.overdue, ...taskBoard.today],
            progress: ref.watch(todayProgressProvider),
          );
          final reminders = _RemindersCard(
            overdue: reminderBoard.overdue,
            next24h: reminderBoard.next24h,
          );
          final digest = ref.watch(digestProvider)
              ? _DigestCard(
                  progress: ref.watch(todayProgressProvider),
                  overdue: taskBoard.overdue.length,
                  reminders: reminderBoard.overdue.length +
                      reminderBoard.next24h.length,
                  onDismiss: () => ref.read(digestProvider.notifier).dismiss(),
                )
              : null;
          const inbox = _InboxCard();

          return RefreshIndicator(
            onRefresh: () => _sync(ref),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [header, today, reminders],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ?digest,
                              const SizedBox(height: 12),
                              inbox,
                            ],
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        header,
                        today,
                        reminders,
                        ?digest,
                        inbox,
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.greeting, required this.date});

  final String greeting;
  final String date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          greeting,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          date,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

/// Everything due today or earlier, with a bar for how much is done.
class _TodayTasksCard extends ConsumerWidget {
  const _TodayTasksCard({required this.tasks, required this.progress});

  /// Overdue first, then the rest of today — both already sorted by due date.
  final List<Task> tasks;
  final TodayProgress progress;

  /// Cap so one long list cannot push the rest of the dashboard off screen.
  static const _shown = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final repo = ref.read(taskRepositoryProvider);
    final visible = tasks.take(_shown).toList();
    final hidden = tasks.length - visible.length;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.checklist, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(child: Text('Today', style: theme.textTheme.titleLarge)),
                Text(
                  progress.isEmpty
                      ? 'Nothing due'
                      : '${progress.done} of ${progress.total} done',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Hidden rather than indeterminate when nothing is due: an
            // endlessly spinning bar reads as "still loading", and this
            // screen has nothing left to load.
            if (!progress.isEmpty) ...[
              LinearProgressIndicator(
                value: progress.fraction,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 8),
            ],
            if (tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  // An empty open list means two quite different things
                  // depending on whether the bar above is full.
                  progress.isEmpty || progress.done == 0
                      ? 'Nothing due today.'
                      : 'All done for today.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              )
            else ...[
              for (final task in visible)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Checkbox(
                    value: task.status == 'completed',
                    shape: const CircleBorder(),
                    onChanged: (_) => repo.toggleComplete(task),
                  ),
                  title: Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(fmtDay(task.dueDate)),
                ),
              if (hidden > 0 || tasks.length > _shown)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => context.go('/tasks'),
                    icon: const Icon(Icons.chevron_right, size: 18),
                    label: Text(
                      hidden > 0 ? '$hidden more' : 'See all',
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RemindersCard extends StatelessWidget {
  const _RemindersCard({required this.overdue, required this.next24h});

  final List<Reminder> overdue;
  final List<Reminder> next24h;

  static const _shown = 5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Overdue first — anything already late is the more urgent answer to
    // "what is coming up?".
    final visible = [...overdue, ...next24h].take(_shown).toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.alarm, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Upcoming', style: theme.textTheme.titleLarge),
                ),
                if (overdue.isNotEmpty)
                  Text(
                    '${overdue.length} overdue',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No reminders in the next 24 hours.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              )
            else ...[
              for (final r in visible)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    r.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${fmtDay(r.remindAt)} · ${fmtTime(r.remindAt)}',
                    style: TextStyle(
                      color: overdue.contains(r)
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.outline,
                  ),
                  onTap: () => context.go('/reminders'),
                ),
            ],
            if ([...overdue, ...next24h].length > _shown)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => context.go('/reminders'),
                  icon: const Icon(Icons.chevron_right, size: 18),
                  label: const Text('See all'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The once-a-day summary Windows gets instead of a scheduled morning toast —
/// scheduled notifications cannot fire while the tray app is not running, so
/// the first open after the day resets is where it lands.
class _DigestCard extends StatelessWidget {
  const _DigestCard({
    required this.progress,
    required this.overdue,
    required this.reminders,
    required this.onDismiss,
  });

  final TodayProgress progress;
  final int overdue;
  final int reminders;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = [
      (Icons.check_circle_outline, '${progress.done} completed today'),
      if (overdue > 0)
        (Icons.error_outline, '$overdue task${overdue == 1 ? '' : 's'} overdue'),
      if (reminders > 0)
        (Icons.notifications_none, '$reminders reminder${reminders == 1 ? '' : 's'} coming up'),
      if (overdue == 0 && reminders == 0 && progress.done == 0)
        (Icons.wb_sunny_outlined, 'Nothing scheduled yet'),
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Morning digest',
                      style: theme.textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: 'Dismiss for today',
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: onDismiss,
                ),
              ],
            ),
            for (final (icon, label) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(child: Text(label)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Newest mail across every connected account.
///
/// A summary rather than a list: three lines is enough to tell whether
/// anything needs attention, which is what the dashboard is for. Tapping goes
/// to the full inbox.
class _InboxCard extends ConsumerWidget {
  const _InboxCard();

  static const _shown = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final emails = ref.watch(recentEmailsProvider).value ?? const <Email>[];
    final hasAccounts =
        (ref.watch(emailAccountsProvider).value ?? const <EmailAccount>[])
            .isNotEmpty;
    final unread = ref.watch(unreadEmailCountProvider).value ?? 0;
    final highlights = emails.take(_shown).toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go('/inbox'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.inbox, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Inbox', style: theme.textTheme.titleLarge),
                  ),
                  if (unread > 0)
                    Text(
                      '$unread unread',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: theme.colorScheme.primary),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (highlights.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    hasAccounts
                        ? 'No mail yet.'
                        : 'Connect a Gmail or Outlook account in Settings.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                )
              else
                for (final email in highlights)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        // Fixed gutter, so read rows stay aligned with unread
                        // ones rather than jumping sideways.
                        if (!email.isRead)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 10),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                          )
                        else
                          const SizedBox(width: 18),
                        Expanded(
                          child: Text(
                            [
                              email.fromName ?? email.fromEmail ?? 'Unknown',
                              if (email.subject.isNotEmpty) email.subject,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          fmtWhen(email.receivedAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
