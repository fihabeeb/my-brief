import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'core/settings/app_settings.dart';
import 'core/supabase/supabase_service.dart';
import 'core/time/app_timezone.dart';
import 'core/utils/logger.dart';
import 'core/window/tray_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initLogging();

  // Must happen before the first frame: minimise-to-tray intercepts the
  // window's close button, and window_manager only supports that once the
  // plugin knows about the window. Guarded because there is no window to
  // manage on platforms without a desktop shell.
  if (TrayService.isSupported) {
    try {
      await windowManager.ensureInitialized();
    } catch (e, st) {
      log.warning('Window manager unavailable; tray features disabled', e, st);
    }
  }

  // Loaded before the first frame so app settings read synchronously.
  final prefs = await SharedPreferences.getInstance();

  // Resolves the device timezone so recurrence and "notify at 09:00" follow
  // local wall-clock time (DST-safe). Falls back to UTC internally on failure.
  await AppTimezone.init();

  // Only initialise Supabase when credentials are provided via
  // --dart-define / --dart-define-from-file. This keeps the app runnable on
  // both platforms before any backend exists (Phase 0 "unconfigured" mode).
  await SupabaseService.initIfConfigured();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MyApp(),
    ),
  );
}
