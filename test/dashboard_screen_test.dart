import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mybrief/core/data/reminder_repository.dart';
import 'package:mybrief/core/data/task_repository.dart';
import 'package:mybrief/core/database/app_database.dart';
import 'package:mybrief/core/database/database_provider.dart';
import 'package:mybrief/core/settings/app_settings.dart';
import 'package:mybrief/features/dashboard/dashboard_screen.dart';

/// Renders the dashboard directly rather than through the router: the route to
/// it sits behind Supabase auth, and the point here is the widget tree, not the
/// redirect.
Future<AppDatabase> _pumpDashboard(
  WidgetTester tester, {
  Map<String, Object> initialPrefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(initialPrefs);
  final prefs = await SharedPreferences.getInstance();
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
      ],
      child: const MaterialApp(home: DashboardScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

void main() {
  testWidgets('shows today\'s tasks and upcoming reminders', (tester) async {
    final db = await _pumpDashboard(tester);

    await TaskRepository(db).upsert(
      userId: 'u1',
      title: 'Pay the electricity bill',
      dueDate: DateTime.utc(2026, 6, 16),
    );
    await ReminderRepository(db).upsert(
      userId: 'u1',
      title: 'Call Sam',
      remindAt: DateTime.now().toUtc().add(const Duration(hours: 2)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Pay the electricity bill'), findsOneWidget);
    expect(find.text('Call Sam'), findsOneWidget);
    // First open with nothing recorded yet, so the digest is offered.
    expect(find.text('Morning digest'), findsOneWidget);
    expect(find.text('Inbox'), findsOneWidget);
    expect(
      find.text('Connect a Gmail or Outlook account in Settings.'),
      findsOneWidget,
      reason: 'with no mail connected the card should say how to fix that',
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('hides the digest once it has been seen today',
      (tester) async {
    await _pumpDashboard(
      tester,
      initialPrefs: {'digest_shown_for': DateTime.now().toIso8601String()},
    );

    expect(find.text('Morning digest'), findsNothing);
    expect(find.text('Today'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('completing a task from the dashboard marks it off',
      (tester) async {
    final db = await _pumpDashboard(tester);
    final repo = TaskRepository(db);
    await repo.upsert(
      userId: 'u1',
      title: 'Send the invoice',
      dueDate: DateTime.utc(2026, 6, 16),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    // The write itself is repository behaviour, covered in
    // task_repository_test.dart; what matters here is that the card reacts.
    expect(
      find.text('Send the invoice'),
      findsNothing,
      reason: 'it should drop out of the open list straight away',
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
