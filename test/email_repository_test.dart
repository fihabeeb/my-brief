import 'package:drift/drift.dart' hide Column;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mybrief/core/data/email_repository.dart';
import 'package:mybrief/core/database/app_database.dart';

void main() {
  late AppDatabase db;
  late EmailRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = EmailRepository(db);
  });

  tearDown(() => db.close());

  EmailsCompanion mail(String id, {String account = 'a1', DateTime? at}) =>
      EmailsCompanion.insert(
        id: id,
        userId: 'u1',
        accountId: account,
        providerMessageId: 'pm-$id',
        subject: const Value('Subject'),
        receivedAt: at ?? DateTime.utc(2024, 1, 1),
        fetchedAt: DateTime.utc(2024, 1, 7),
      );

  EmailAccountsCompanion account(String id, {String address = 'x@y.z'}) =>
      EmailAccountsCompanion.insert(
        id: id,
        userId: 'u1',
        provider: 'gmail',
        emailAddress: address,
        secretRef: 'vault/$id',
        createdAt: DateTime.utc(2024, 1, 1),
      );

  group('EmailRepository', () {
    test('re-pulling an overlapping window updates rather than duplicates',
        () async {
      await repo.upsertEmails([mail('m1', at: DateTime.utc(2024, 1, 5))]);
      // A refresh slides forward but still includes yesterday's row.
      await repo.upsertEmails([
        mail('m1', at: DateTime.utc(2024, 1, 5)),
        mail('m2', at: DateTime.utc(2024, 1, 6)),
      ]);

      final list = await repo.watchRecent().first;
      expect(list.map((e) => e.id), ['m2', 'm1']);
    });

    test('pruneTo keeps the newest mail and leaves a short table alone',
        () async {
      await repo.upsertEmails([
        mail('old', at: DateTime.utc(2024, 1, 1)),
        mail('mid', at: DateTime.utc(2024, 1, 2)),
        mail('new', at: DateTime.utc(2024, 1, 3)),
      ]);

      // Under the cap: nothing should be touched.
      await repo.pruneTo(10);
      expect(await repo.watchRecent().first, hasLength(3));

      await repo.pruneTo(2);
      final kept = await repo.watchRecent().first;
      expect(kept.map((e) => e.id), ['new', 'mid']);
    });

    test('mail belonging to a dropped account goes with it', () async {
      await repo.upsertAccount(account('a1'));
      await repo.upsertEmails([mail('m1', account: 'a1')]);

      await repo.deleteAccount('a1');

      expect(await repo.watchAccounts().first, isEmpty);
      expect(await repo.watchRecent().first, isEmpty);
    });

    test('deleteAccountsExcept only drops what the server forgot', () async {
      await repo.upsertAccount(account('a1', address: 'a@y.z'));
      await repo.upsertAccount(account('a2', address: 'b@y.z'));

      await repo.deleteAccountsExcept({'a2'});

      final kept = await repo.watchAccounts().first;
      expect(kept.map((a) => a.id), ['a2']);
    });

    test('unread count spans every connected mailbox', () async {
      await repo.upsertEmails([
        mail('m1', account: 'a1'),
        mail('m2', account: 'a1'),
        mail('m3', account: 'a2'),
      ]);
      expect(await repo.watchUnreadCount().first, 3);

      final read = (await repo.watchRecent().first).first;
      await repo
          .upsertEmails([mail(read.id, at: read.receivedAt).copyWith(
              isRead: const Value(true))]);

      expect(await repo.watchUnreadCount().first, 2);
    });
  });
}
