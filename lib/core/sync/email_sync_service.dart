import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/email_repository.dart';
import '../database/app_database.dart';
import '../supabase/supabase_service.dart';

final emailSyncServiceProvider = Provider<EmailSyncService>(
    (ref) => EmailSyncService(ref.watch(emailRepositoryProvider)));

/// One-way pull of the connected mailboxes into the local mirror.
///
/// Deliberately separate from `SyncService`. That class pushes local changes
/// and merges them back with a last-write-wins rule on `updated_at`, which is
/// the right model for tasks and reminders the user edits on this device.
/// Email has no local edits and exactly one writer in the cloud, so it needs
/// none of that machinery — just a mirror that keeps up.
class EmailSyncService {
  EmailSyncService(this._repo);

  final EmailRepository _repo;

  /// How much mail to keep locally: enough to browse a busy week, small
  /// enough that the table stays quick on a phone.
  static const _limit = 200;

  bool get _enabled => SupabaseService.isConfigured;
  String get _uid => SupabaseService.auth.currentUser?.id ?? '';

  Future<void> syncNow() async {
    if (!_enabled || _uid.isEmpty) return;
    final uid = _uid;
    final accountIds = await _pullAccounts(uid);
    await _pullEmails(uid, accountIds);
    await _repo.pruneTo(_limit);
  }

  /// Mirrors the account list, dropping any local account the server has
  /// forgotten — the user disconnected it on another device. Safe to delete
  /// on mismatch here because the client never creates an account of its own;
  /// the Edge Function is what writes one, once OAuth has told it the address.
  ///
  /// Returns the account ids so the mail pull can reconcile each mailbox
  /// separately against the server's complete retained window.
  Future<List<String>> _pullAccounts(String uid) async {
    final remote = await SupabaseService.client
        .from('email_accounts')
        .select()
        .eq('user_id', uid)
        .eq('provider', 'gmail')
        .order('email_address', ascending: true);

    final keep = <String>{};
    for (final raw in remote) {
      final row = Map<String, dynamic>.from(raw as Map);
      final account = _account(row);
      keep.add(row['id'] as String);
      await _repo.upsertAccount(account);
    }
    await _repo.deleteAccountsExcept(keep);
    return keep.toList();
  }

  /// Pulls one account at a time so a row missing from the server window can
  /// be treated as deleted. The server retains the newest 200 messages per
  /// account, and we ask for one extra row: if it comes back, retention is
  /// not behaving as expected and deleting would be unsafe.
  Future<void> _pullEmails(String uid, List<String> accountIds) async {
    for (final accountId in accountIds) {
      final remote = await SupabaseService.client
          .from('emails')
          .select()
          .eq('user_id', uid)
          .eq('account_id', accountId)
          .order('received_at', ascending: false)
          .limit(_limit + 1);

      final rows = <EmailsCompanion>[
        for (final raw in remote)
          _email(Map<String, dynamic>.from(raw as Map)),
      ];
      await _repo.reconcileAccountEmails(
        accountId,
        rows,
        complete: rows.length <= _limit,
      );
    }
  }

  EmailAccountsCompanion _account(Map<String, dynamic> row) =>
      EmailAccountsCompanion.insert(
        id: row['id'] as String,
        userId: row['user_id'] as String,
        provider: row['provider'] as String,
        emailAddress: row['email_address'] as String,
        displayName: Value(row['display_name'] as String?),
        status: Value(row['status'] as String? ?? 'connected'),
        lastError: Value(row['last_error'] as String?),
        syncCursor: Value(row['sync_cursor'] as String?),
        lastSyncedAt: Value(_ts(row['last_synced_at'])),
        secretRef: row['secret_ref'] as String,
        createdAt: _ts(row['created_at']) ?? DateTime.now().toUtc(),
      );

  EmailsCompanion _email(Map<String, dynamic> row) => EmailsCompanion.insert(
        id: row['id'] as String,
        userId: row['user_id'] as String,
        accountId: row['account_id'] as String,
        providerMessageId: row['provider_message_id'] as String,
        threadId: Value(row['thread_id'] as String?),
        fromName: Value(row['from_name'] as String?),
        fromEmail: Value(row['from_email'] as String?),
        subject: Value(row['subject'] as String? ?? ''),
        snippet: Value(row['snippet'] as String?),
        receivedAt: _ts(row['received_at']) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        isRead: Value(row['is_read'] as bool? ?? false),
        isImportant: Value(row['is_important'] as bool? ?? false),
        hasAttachments: Value(row['has_attachments'] as bool? ?? false),
        webLink: Value(row['web_link'] as String?),
        fetchedAt: _ts(row['fetched_at']) ?? DateTime.now().toUtc(),
      );

  static DateTime? _ts(dynamic value) =>
      value == null ? null : DateTime.parse(value as String).toUtc();
}
