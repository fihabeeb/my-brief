import 'dart:io';

import 'package:launch_at_startup/launch_at_startup.dart';

/// Start-on-login support.
///
/// Reminders on Windows are fired by this process, so an app the user never
/// opens is an app that never reminds them. This writes the stored preference
/// through to the OS registry on every launch.
///
/// Preferences are the source of truth, not the registry: if the entry is
/// edited or disabled outside the app (Task Manager's Startup tab, an IT
/// policy), the next launch puts it back in line with what the user chose
/// here rather than silently diverging.
const _appName = 'My Brief';

/// Applies [enabled] to the OS startup registration.
///
/// Never throws and never blocks launch: a machine that refuses the registry
/// write keeps working, it just does not auto-start.
Future<void> applyStartOnLogin({required bool enabled}) async {
  if (!Platform.isWindows) return;
  try {
    final launcher = LaunchAtStartup.instance;
    launcher.setup(
      appName: _appName,
      // The installed executable. Under `flutter run` this points at the debug
      // build, which is why start-on-login is a Settings toggle rather than
      // something that switches itself on during development.
      appPath: Platform.resolvedExecutable,
    );
    if (enabled) {
      await launcher.enable();
    } else {
      await launcher.disable();
    }
  } catch (_) {
    // Startup registration is a convenience; never let it fail the app.
  }
}

/// Reads the OS's current registration, for showing reality rather than intent.
Future<bool> isStartOnLoginEnabled() async {
  if (!Platform.isWindows) return false;
  try {
    final launcher = LaunchAtStartup.instance;
    launcher.setup(
      appName: _appName,
      appPath: Platform.resolvedExecutable,
    );
    return await launcher.isEnabled();
  } catch (_) {
    return false;
  }
}
