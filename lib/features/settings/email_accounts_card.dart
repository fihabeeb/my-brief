import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/data/email_repository.dart';
import '../../core/database/app_database.dart';
import '../../core/supabase/supabase_service.dart';
import '../../core/utils/format.dart';
import '../inbox/inbox_providers.dart';

/// Connecting and disconnecting mailboxes.
///
/// The client never performs the OAuth exchange itself: it asks the
/// `oauth-start` Edge Function for a signed authorisation URL, then hands the
/// browser over. That keeps the provider client secret on the server and lets
/// the callback mint the account row with the address it learns from the
/// provider — which is why there is no "pending" account state here at all.
class EmailAccountsCard extends ConsumerWidget {
  const EmailAccountsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Nothing rendered while loading rather than a spinner: this card sits on
    // a settings list that is already usable, and a flash of indeterminate
    // progress would say more than it knows.
    final accounts =
        ref.watch(emailAccountsProvider).value ?? const <EmailAccount>[];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Email accounts', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Mail is read into the dashboard. Nothing is ever sent from '
              'this app.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            for (final account in accounts)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.mail_outline,
                  color: theme.colorScheme.primary,
                ),
                title: Text(account.emailAddress),
                subtitle: Text(_statusOf(account)),
                trailing: IconButton(
                  tooltip: 'Disconnect',
                  icon: Icon(Icons.link_off, color: theme.colorScheme.error),
                  onPressed: () => _disconnect(context, account),
                ),
              ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: () => _connect(context),
              icon: const Icon(Icons.mail_outline, size: 18),
              label: const Text('Connect Gmail'),
            ),
          ],
        ),
      ),
    );
  }

  String _statusOf(EmailAccount account) {
    switch (account.status) {
      case 'needs_reauth':
        return 'Needs reconnecting — the provider revoked access';
      case 'error':
        return account.lastError ?? 'Sync failing';
      default:
        final at = account.lastSyncedAt;
        return at == null ? 'Connected' : 'Last synced ${fmtDateTime(at)}';
    }
  }

  /// Asks the Edge Function for a signed authorisation URL and hands the
  /// browser to it.
  ///
  /// The function mints the `state`, so a link opened from elsewhere cannot
  /// attach a mailbox to this account — the check lives where the JWT can be
  /// verified, not in a query parameter this app would be free to fake.
  Future<void> _connect(BuildContext context) async {
    try {
      final result = await SupabaseService.client.functions.invoke(
        'oauth-start',
        body: {'provider': 'gmail'},
      );
      final url = (result.data as Map?)?['authorize_url'] as String?;
      if (url == null) throw const FormatException('no authorisation URL');

      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) throw Exception('browser would not open');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not start connecting ($e). The email functions may not be '
            'deployed yet.',
          ),
        ),
      );
    }
  }

  Future<void> _disconnect(BuildContext context, EmailAccount account) async {
    // Captured before the first await: the dialog below suspends this method,
    // and both would otherwise be read off a context that may no longer be
    // mounted by the time the user answers.
    final messenger = ScaffoldMessenger.of(context);
    final repo = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(emailRepositoryProvider);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect account?'),
        content: Text(
          '${account.emailAddress} will stop syncing and its mail will be '
          'removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      // Revokes the tokens and deletes the row server-side first: removing it
      // locally alone would just bring it back on the next pull.
      await SupabaseService.client.functions.invoke(
        'email-disconnect',
        body: {'account_id': account.id},
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not disconnect ($e)')),
      );
      return;
    }

    // The pull will also drop it, but doing it here makes the UI respond now
    // rather than after the next sync.
    await repo.deleteAccount(account.id);
  }
}
