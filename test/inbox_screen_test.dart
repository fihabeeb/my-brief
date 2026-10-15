import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mybrief/core/database/app_database.dart';
import 'package:mybrief/core/database/database_provider.dart';
import 'package:mybrief/core/settings/app_settings.dart';
import 'package:mybrief/features/inbox/inbox_screen.dart';

/// Lets the Drift stream land.
///
/// Deliberately not `pumpAndSettle`: the inbox shows an indeterminate
/// spinner while it loads, and that animates forever, so settling would spin
/// until the test times out.
Future<void> _flush(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<AppDatabase> _pumpInbox(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
      ],
      child: const MaterialApp(home: InboxScreen()),
    ),
  );
  await _flush(tester);
  return db;
}

Email _email({
  String id = 'e1',
  String subject = 'Dinner on Friday',
  String? fromName = 'Sam Jones',
  String? fromEmail = 'sam.jones@example.com',
  bool isRead = false,
  bool isImportant = false,
  String? snippet = 'Are we still on for 7ish?',
  String? webLink = 'https://mail.google.com/mail/u/0/#all/e1',
  DateTime? receivedAt,
}) =>
    Email(
      id: id,
      userId: 'u1',
      accountId: 'a1',
      providerMessageId: 'g-$id',
      subject: subject,
      fromName: fromName,
      fromEmail: fromEmail,
      isRead: isRead,
      isImportant: isImportant,
      snippet: snippet,
      webLink: webLink,
      hasAttachments: false,
      receivedAt: receivedAt ?? DateTime.now().toUtc(),
      fetchedAt: DateTime.now().toUtc(),
    );

void main() {
  testWidgets('points at Settings when no account is connected', (tester) async {
    await _pumpInbox(tester);

    expect(find.text('No account connected'), findsOneWidget);
    expect(find.text('Go to Settings'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('says so plainly when an account has no mail yet', (tester) async {
    final db = await _pumpInbox(tester);
    await db.into(db.emailAccounts).insert(
          EmailAccountsCompanion.insert(
            id: 'a1',
            userId: 'u1',
            provider: 'gmail',
            emailAddress: 'me@example.com',
            secretRef: 'email_gmail_a1',
            createdAt: DateTime.now().toUtc(),
          ),
        );
    await _flush(tester);

    expect(find.text('No mail yet'), findsOneWidget);
    expect(find.text('Go to Settings'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('renders a merged inbox with sender, subject and time',
      (tester) async {
    final db = await _pumpInbox(tester);
    await db.batch((batch) {
      batch.insertAll(db.emails, [
        _email(),
        _email(
          id: 'e2',
          subject: 'Invoice 4471',
          fromName: null,
          fromEmail: 'billing@example.com',
          isRead: true,
          receivedAt:
              DateTime.now().toUtc().subtract(const Duration(days: 2)),
        ),
      ]);
    });
    await _flush(tester);

    expect(find.text('Dinner on Friday'), findsOneWidget);
    expect(find.text('Invoice 4471'), findsOneWidget);
    // No display name on the second, so the address is used instead of an
    // anonymous row.
    expect(find.textContaining('billing@example.com'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('a message with no sender or subject degrades politely',
      (tester) async {
    final db = await _pumpInbox(tester);
    await db.into(db.emails).insert(
          _email(fromName: null, fromEmail: null, subject: '', snippet: null),
        );
    await _flush(tester);

    expect(find.text('(no subject)'), findsOneWidget);
    expect(find.text('Unknown sender'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
