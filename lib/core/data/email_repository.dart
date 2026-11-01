import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/database_provider.dart';

final emailRepositoryProvider = Provider<EmailRepository>(
  (ref) => EmailRepository(ref.watch(appDatabaseProvider)),
);

/// Local mirror of the connected mailboxes.
///
/// Everything here is read-only from the app's point of view: mail is written
/// by the Edge Functions in the cloud and pulled down, never composed on the
/// device. That is the whole reason this repository has no outbox-style
/// `markNeedsSync` — there is nothing to push back.
class EmailRepository {
  EmailRepository(this._db);

  final AppDatabase _db;

  /// Newest mail first, merged across every connected account.
  Stream<List<Email>> watchRecent({int limit = 50}) =>
      (_db.select(_db.emails)
            ..orderBy([(e) => OrderingTerm.desc(e.receivedAt)])
            ..limit(limit))
          .watch();

  Stream<List<EmailAccount>> watchAccounts() => (_db.select(
    _db.emailAccounts,
  )..orderBy([(a) => OrderingTerm.asc(a.emailAddress)])).watch();

  Stream<int> watchUnreadCount() {
    final unread = _db.emails.id.count(filter: _db.emails.isRead.equals(false));
    return (_db.selectOnly(
      _db.emails,
    )..addColumns([unread])).map((row) => row.read(unread) ?? 0).watchSingle();
  }

  /// Brings the local copy of one mailbox up to date with a pulled batch.
  ///
  /// Upserting by id is what makes a refresh that overlaps the previous window
  /// rewrite rather than duplicate. This method never deletes; once the Edge
  /// Function has used Gmail history to decide what is gone,
  /// [reconcileAccountEmails] applies the complete per-account window.
  Future<void> upsertEmails(List<Insertable<Email>> rows) => _db.batch((batch) {
    batch.insertAllOnConflictUpdate(_db.emails, rows);
  });

  /// Keeps only the [limit] newest messages.
  ///
  /// Local growth is otherwise unbounded: each pull slides the window forward
  /// and the rows behind it would stay forever.
  Future<void> pruneTo(int limit) async {
    final rows =
        await (_db.select(_db.emails)
              ..orderBy([(e) => OrderingTerm.desc(e.receivedAt)])
              ..limit(limit))
            .get();
    if (rows.length < limit) return; // Still under the cap.

    final keep = rows.map((e) => e.id).toSet();
    await (_db.delete(_db.emails)..where((e) => e.id.isNotIn(keep))).go();
  }

  Future<void> upsertAccount(Insertable<EmailAccount> account) =>
      _db.into(_db.emailAccounts).insertOnConflictUpdate(account);

  /// Reconciles one account with the complete set the server retains.
  ///
  /// The server keeps the newest 200 messages per account. When [complete] is
  /// true, the pulled rows are that whole set, so anything local that is not
  /// in it was deleted or archived at the provider and must go. When false —
  /// a defensive overflow path — only upsert; deleting from a partial window
  /// would wipe mail that is still there.
  Future<void> reconcileAccountEmails(
    String accountId,
    List<EmailsCompanion> rows, {
    required bool complete,
  }) => _db.transaction(() async {
    if (rows.isNotEmpty) {
      await _db.batch((batch) {
        batch.insertAllOnConflictUpdate(_db.emails, rows);
      });
    }
    if (!complete) return;

    final keep = <String>{};
    for (final row in rows) {
      if (row.id.present) keep.add(row.id.value);
    }

    if (keep.isEmpty) {
      await (_db.delete(
        _db.emails,
      )..where((e) => e.accountId.equals(accountId))).go();
    } else {
      await (_db.delete(
        _db.emails,
      )..where((e) => e.accountId.equals(accountId) & e.id.isNotIn(keep))).go();
    }
  });

  /// Drops every account the server no longer knows about — the user
  /// disconnected it elsewhere — and the mail that belonged to it.
  Future<void> deleteAccountsExcept(Set<String> keep) =>
      _db.transaction(() async {
        if (keep.isEmpty) {
          await _db.delete(_db.emails).go();
          await _db.delete(_db.emailAccounts).go();
          return;
        }

        await (_db.delete(
          _db.emails,
        )..where((e) => e.accountId.isNotIn(keep))).go();
        await (_db.delete(
          _db.emailAccounts,
        )..where((a) => a.id.isNotIn(keep))).go();
      });

  /// Disconnecting drops the mail with it — a mailbox the user has removed
  /// should not linger as readable history.
  Future<void> deleteAccount(String accountId) => _db.transaction(() async {
    await (_db.delete(
      _db.emails,
    )..where((e) => e.accountId.equals(accountId))).go();
    await (_db.delete(
      _db.emailAccounts,
    )..where((a) => a.id.equals(accountId))).go();
  });
}
