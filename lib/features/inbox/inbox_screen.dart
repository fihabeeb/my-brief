import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/database/app_database.dart';
import '../../core/sync/sync_service.dart';
import '../../core/utils/format.dart';
import 'inbox_providers.dart';

/// The merged inbox across every connected account.
///
/// Reading happens in the browser: a tap opens the message at the provider via
/// its `webLink`. The app deliberately keeps only a preview locally (see the
/// `emails` table), so it is a triage surface rather than a mail reader — the
/// distinction is worth being explicit about, because a user who taps through
/// and lands in Gmail should not be surprised by it.
class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emails = ref.watch(recentEmailsProvider);
    final hasAccounts =
        (ref.watch(emailAccountsProvider).value ?? const <EmailAccount>[])
            .isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inbox'),
        actions: [
          IconButton(
            tooltip: 'Sync now',
            icon: const Icon(Icons.sync),
            onPressed: () => ref.read(syncServiceProvider).syncNow(),
          ),
        ],
      ),
      body: emails.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Message(
          icon: Icons.error_outline,
          title: 'Could not load mail',
          detail: '$e',
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return _Message(
              icon: Icons.inbox_outlined,
              title: hasAccounts ? 'No mail yet' : 'No account connected',
              detail: hasAccounts
                  ? 'New mail appears here after the next sync.'
                  : 'Connect a Gmail or Outlook account in Settings to '
                      'bring your mail into the dashboard.',
              action: hasAccounts
                  ? null
                  : (
                      label: 'Go to Settings',
                      onTap: () => context.go('/settings'),
                    ),
            );
          }
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) => _EmailTile(email: rows[i]),
          );
        },
      ),
    );
  }
}

class _EmailTile extends StatelessWidget {
  const _EmailTile({required this.email});

  final Email email;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = !email.isRead;
    // Fall back to the address when the provider gave no display name, rather
    // than showing an anonymous row.
    final sender = email.fromName ?? email.fromEmail ?? 'Unknown sender';

    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: unread
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        child: Text(
          sender.isEmpty ? '?' : sender.characters.first.toUpperCase(),
          style: theme.textTheme.titleSmall?.copyWith(
            color: unread
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      title: Text(
        email.subject.isEmpty ? '(no subject)' : email.subject,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: unread ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      subtitle: Text(
        [sender, if (email.snippet != null) email.snippet!].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            fmtWhen(email.receivedAt),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (email.isImportant)
            Icon(Icons.star, size: 16, color: theme.colorScheme.primary),
        ],
      ),
      onTap: email.webLink == null ? null : () => _open(context, email.webLink!),
    );
  }

  Future<void> _open(BuildContext context, String link) async {
    final uri = Uri.tryParse(link);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the message')),
      );
    }
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });

  final IconData icon;
  final String title;
  final String detail;
  final ({String label, VoidCallback onTap})? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: 20),
              FilledButton(
                onPressed: action!.onTap,
                child: Text(action!.label),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
