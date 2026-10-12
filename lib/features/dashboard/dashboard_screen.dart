import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/supabase/supabase_service.dart';
import '../reminders/reminder_providers.dart';
import '../tasks/task_providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user =
        SupabaseService.isConfigured ? SupabaseService.auth.currentUser : null;

    final taskBoard = ref.watch(taskBoardProvider);
    final reminderBoard = ref.watch(reminderBoardProvider);

    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 18
            ? 'Good afternoon'
            : 'Good evening';
    final dateStr = DateFormat('EEEE, d MMMM yyyy').format(now);

    return Scaffold(
      appBar: AppBar(title: const Text('My Brief')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            user?.email != null ? '$greeting, ${user!.email}' : greeting,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            dateStr,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          _StatCard(
            icon: Icons.checklist,
            title: 'Tasks',
            value: '${taskBoard.openCount} open',
            subtitle:
                '${taskBoard.today.length} today · ${taskBoard.overdue.length} overdue',
            onTap: () => context.go('/tasks'),
          ),
          _StatCard(
            icon: Icons.alarm,
            title: 'Reminders',
            value: '${reminderBoard.activeCount} active',
            subtitle:
                '${reminderBoard.next24h.length} in next 24h · ${reminderBoard.overdue.length} overdue',
            onTap: () => context.go('/reminders'),
          ),
          _StatCard(
            icon: Icons.inbox,
            title: 'Inbox highlights',
            value: 'Coming soon',
            subtitle: 'Email integration arrives in Phase 4',
            onTap: null,
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 28, color: theme.colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    value,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (onTap != null)
                    Icon(Icons.chevron_right,
                        color: theme.colorScheme.outline),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
