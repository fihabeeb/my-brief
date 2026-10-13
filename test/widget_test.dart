import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mybrief/app/app.dart';
import 'package:mybrief/app/tray_bootstrap.dart';
import 'package:mybrief/core/database/app_database.dart';
import 'package:mybrief/core/database/database_provider.dart';
import 'package:mybrief/core/notifications/notification_service.dart';
import 'package:mybrief/core/settings/app_settings.dart';
import 'package:mybrief/core/window/tray_service.dart';

void main() {
  testWidgets('renders setup screen when Supabase is unconfigured',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
          // Notifications are local-first and start even without a backend,
          // so the widget under test must not touch a real toast plugin.
          notificationServiceProvider
              .overrideWithValue(const UnsupportedNotificationService()),
          // The test host is Windows, so the real bootstrap would create a
          // native tray icon. This instance is never initialised, so no
          // native call is made.
          trayBootstrapProvider.overrideWithValue(
            TrayService(minimizeToTray: () => true),
          ),
        ],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    // No credentials in tests => the app routes to the setup screen.
    expect(find.text('Connect your Supabase backend'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);

    // Unmount and flush. Tearing down the tree cancels the scheduler's Drift
    // subscriptions, which defer their stream close by a zero-duration timer.
    // `pump()` with no duration only drains microtasks, so the explicit
    // `Duration.zero` is what makes fake_async actually run those timers.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
