import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/reminder_repository.dart';
import '../core/data/task_repository.dart';
import '../core/database/database_provider.dart';
import '../core/notifications/due_planner.dart';
import '../core/notifications/notification_intent.dart';
import '../core/notifications/notification_scheduler.dart';
import '../core/notifications/notification_service.dart';
import '../core/settings/app_settings.dart';
import '../core/time/app_timezone.dart';
import '../core/window/window_activation.dart';
import 'router.dart';

/// Starts the in-process notification scheduler (Phase 2, Windows).
///
/// Rebuilt whenever a relevant setting changes, so switching notifications off
/// or moving the task-alert hour takes effect immediately: the previous
/// scheduler's subscriptions and timers are disposed first.
final notificationBootstrapProvider = Provider<void>((ref) {
  final settings = ref.watch(appSettingsProvider);
  if (!settings.notificationsEnabled) return;

  final service = ref.read(notificationServiceProvider);
  final router = ref.read(routerProvider);
  final db = ref.watch(appDatabaseProvider);

  final scheduler = NotificationScheduler(
    service: service,
    reminders: ReminderRepository(db),
    tasks: TaskRepository(db),
    prefs: ref.read(sharedPreferencesProvider),
    planner: DuePlanner(
      location: AppTimezone.location,
      taskNotifyHour: settings.taskNotifyHour,
      snoozeMinutes: settings.snoozeMinutes,
    ),
    onActivate: activateWindow,
    onNavigate: router.go,
  );

  // Resolves the toast click/action payload into an intent. `init` keeps the
  // latest callback even though the plugin itself initializes only once.
  service.init(onResponse: (payload) =>
      scheduler.handleIntent(NotificationIntent.parse(payload)));

  scheduler.start();
  ref.onDispose(scheduler.stop);
});
