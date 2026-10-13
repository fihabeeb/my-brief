import 'dart:io';

import 'package:window_manager/window_manager.dart';

/// Brings the app window to the foreground.
///
/// Called when a toast is clicked while the app is sitting in the tray. All
/// window_manager calls are guarded: the plugin throws if the window has not
/// been registered yet, and a toast can arrive very early in startup.
Future<void> activateWindow() async {
  if (!Platform.isWindows) return;
  try {
    if (!await windowManager.isVisible()) await windowManager.show();
    await windowManager.focus();
  } catch (_) {
    // Not ready yet or already front-most — nothing useful to do.
  }
}
