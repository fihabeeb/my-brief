import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings/app_settings.dart';
import '../core/window/start_on_login.dart';
import '../core/window/tray_service.dart';

/// Owns the tray icon, minimise-to-tray and start-on-login.
///
/// Created once for the life of the process. The tray has to outlive window
/// rebuilds and route changes, and rebuilding this provider would tear the
/// icon out of the notification area and put it back.
///
/// Settings are deliberately *read*, never watched: a rebuild here would mean
/// destroying and recreating a native tray icon just because a toggle moved.
/// Instead the tray reads the setting at the moment it matters — when the user
/// clicks close — so a change applies immediately without a restart.
final trayBootstrapProvider = Provider<TrayService>((ref) {
  final settings = ref.read(appSettingsProvider);

  final service = TrayService(
    minimizeToTray: () => ref.read(appSettingsProvider).minimizeToTray,
  );
  service.init();

  // Re-asserts the stored preference against the OS on every launch, so an
  // entry changed outside the app is corrected rather than silently diverging.
  applyStartOnLogin(enabled: settings.startOnLogin);

  ref.onDispose(service.dispose);
  return service;
});
