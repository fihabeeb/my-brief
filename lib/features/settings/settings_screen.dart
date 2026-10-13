import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/providers/theme_mode_provider.dart';
import '../../core/settings/app_settings.dart';
import '../../core/supabase/supabase_service.dart';
import '../../core/window/start_on_login.dart';
import '../../core/window/tray_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mode = ref.watch(themeModeProvider);
    final appSettings = ref.watch(appSettingsProvider);
    final notificationsSupported =
        ref.watch(notificationServiceProvider).isSupported;
    final notifier = ref.read(appSettingsProvider.notifier);
    final configured = SupabaseService.isConfigured;
    final email = configured ? SupabaseService.auth.currentUser?.email : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.cloud_outlined),
                  title: const Text('Backend'),
                  subtitle:
                      Text(configured ? 'Supabase connected' : 'Not configured'),
                ),
                if (email != null)
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: const Text('Signed in as'),
                    subtitle: Text(email),
                  ),
              ],
            ),
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Appearance', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.brightness_auto),
                        label: Text('System'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode),
                        label: Text('Light'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode),
                        label: Text('Dark'),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (s) =>
                        ref.read(themeModeProvider.notifier).set(s.first),
                  ),
                ],
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_outlined),
                  title: const Text('Notifications'),
                  subtitle: Text(notificationsSupported
                      ? 'Reminders and due tasks'
                      : 'Not available on this device yet'),
                  value: appSettings.notificationsEnabled,
                  onChanged: notificationsSupported
                      ? notifier.setNotificationsEnabled
                      : null,
                ),
                if (notificationsSupported && appSettings.notificationsEnabled) ...[
                  ListTile(
                    leading: const Icon(Icons.access_time),
                    title: const Text('Task alert time'),
                    subtitle:
                        const Text('Due tasks are announced at this hour'),
                    trailing: DropdownButton<int>(
                      value: appSettings.taskNotifyHour,
                      items: [
                        for (var h = 0; h < 24; h++)
                          DropdownMenuItem(
                            value: h,
                            child:
                                Text('${h.toString().padLeft(2, '0')}:00'),
                          ),
                      ],
                      onChanged: (h) {
                        if (h != null) notifier.setTaskNotifyHour(h);
                      },
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.snooze),
                    title: const Text('Snooze length'),
                    trailing: DropdownButton<int>(
                      // Guarded so a hand-edited prefs value can't make the
                      // dropdown assert on an item that isn't in the list.
                      value: const [5, 10, 15, 30, 60]
                              .contains(appSettings.snoozeMinutes)
                          ? appSettings.snoozeMinutes
                          : 10,
                      items: [
                        for (final m in const [5, 10, 15, 30, 60])
                          DropdownMenuItem(value: m, child: Text('$m min')),
                      ],
                      onChanged: (m) {
                        if (m != null) notifier.setSnoozeMinutes(m);
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (TrayService.isSupported)
            Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.picture_in_picture_alt),
                    title: const Text('Minimise to tray'),
                    subtitle: const Text(
                      'Closing the window keeps My Brief running, '
                      'so reminders still fire',
                    ),
                    value: appSettings.minimizeToTray,
                    onChanged: notifier.setMinimizeToTray,
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.power_settings_new),
                    title: const Text('Start on login'),
                    subtitle: const Text(
                      'Launches at sign-in so due tasks can be announced',
                    ),
                    value: appSettings.startOnLogin,
                    onChanged: (value) {
                      notifier.setStartOnLogin(value);
                      // Written through to the OS immediately; the stored
                      // value is re-asserted on every launch, so an entry
                      // changed outside the app is corrected rather than
                      // silently diverging.
                      applyStartOnLogin(enabled: value);
                    },
                  ),
                ],
              ),
            ),
          if (configured)
            Card(
              child: ListTile(
                leading: Icon(Icons.logout, color: theme.colorScheme.error),
                title: Text(
                  'Sign out',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                onTap: () => ref.read(authControllerProvider.notifier).signOut(),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            'My Brief — Phase 0 foundation',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
