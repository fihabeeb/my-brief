import 'package:drift/drift.dart';

import '../database/app_database.dart';

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

  Stream<List<EmailAccount>> watchAccounts() =>
      (_db.select(_db.emailAccounts)
            ..orderBy([(a) => OrderingTerm.asc(a.emailAddress)]))
          .watch();

  Stream<int> watchUnreadCount() {
    final unread = _db.emails.id.count(filter: _db.emails.isRead.equals(false));
    return (_db.selectOnly(_db.emails)..addColumns([unread]))
        .map((row) => row.read(unread) ?? 0)
        .watchSingle();
  }

  /// Brings the local copy of one account into line with what the server has.
  ///
  /// Upserting by id and then deleting whatever was not in the batch gives the
  /// mirror semantics we want in one transaction: mail deleted at the provider
  /// disappears locally, and a refresh that overlaps the previous window
  /// rewrites rather than duplicates.
  Future<void> mirrorAccount(String accountId, List<Email> rows) =>
      _db.transaction(() async {
        await _db.batch((batch) {
          batch.insertAllOnConflictUpdate(_db.emails, rows);
        });

        final keep = rows.map((row) => row.id).toSet();
        await (_db.delete(_db.emails)
              ..where((e) => e.accountId.equals(accountId) & e.id.isNotIn(keep)))
            .go();
      });

  Future<void> upsertAccount(EmailAccount account) =>
      _db.into(_db.emailAccounts).insertOnConflictUpdate(account);

  /// Disconnecting drops the mail with it — a mailbox the user has removed
  /// should not linger as readable history.
  Future<void> deleteAccount(String accountId) => _db.transaction(() async {
        await (_db.delete(_db.emails)
              ..where((e) => e.accountId.equals(accountId)))
            .go();
        await (_db.delete(_db.emailAccounts)
              ..where((a) => a.id.equals(accountId)))
            .go();
      });
}
