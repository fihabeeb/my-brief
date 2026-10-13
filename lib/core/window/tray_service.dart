import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// The app's presence in the Windows notification area.
///
/// Windows has no supported way to run code while a process is closed, so a
/// reminder can only fire from a running process. The tray is therefore part
/// of the notification feature, not a cosmetic extra: closing the window hides
/// the app instead of ending it, and the tray is how the user gets it back or
/// genuinely quits.
///
/// Deliberately not a Riverpod object: it listens to *native* events and owns
/// native handles, so it is created once and driven by the callbacks below.
/// The one thing it needs from app state — whether to hide or really close —
/// is injected as a getter and read at close time, so the setting applies
/// without a restart.
class TrayService with WindowListener {
  TrayService({required this.minimizeToTray});

  /// Whether closing the window should hide it instead of ending the process.
  ///
  /// A getter, not a bool: read at close time so a Settings toggle applies
  /// immediately, without restarting or rebuilding the native tray icon.
  final bool Function() minimizeToTray;

  TrayIcon? _trayIcon;
  Menu? _menu;
  MenuItem? _openItem;
  MenuItem? _quitItem;
  ListenerId? _trayListenerId;
  ListenerId? _menuListenerId;
  bool _started = false;

  /// The tray, minimise-to-tray and start-on-login only exist on Windows.
  static bool get isSupported => !kIsWeb && Platform.isWindows;

  /// Whether [init] took effect, so callers can tell a real tray from an
  /// unavailable one instead of assuming.
  bool get isRunning => _started;

  /// Creates the notification-area icon and intercepts window close.
  ///
  /// Safe to call repeatedly and safe where there is no tray. A tray icon is a
  /// convenience, so every failure path leaves the app running normally
  /// rather than dead on the first frame.
  Future<bool> init() async {
    if (!isSupported || _started) return _started;
    _started = true;

    try {
      windowManager.addListener(this);

      final icon = TrayIcon.create();
      if (icon == null) {
        _started = false;
        return false;
      }
      _trayIcon = icon;

      final menu = _buildMenu();
      if (menu != null) {
        _menu = menu;
        icon.setContextMenu(menu);
      }

      // A plain click restores the window; right-click opens the menu. Setting
      // the trigger explicitly stops Windows from also popping the menu on
      // left-click, which would swallow the restore.
      icon.setContextMenuTrigger(ContextMenuTrigger.rightClicked);
      icon.setTooltip('My Brief');

      final image = _loadIcon();
      if (image != null) icon.icon = image;

      _trayListenerId = icon.addListener(_onTrayEvent);
      icon.setVisible(true);

      // Only intercept close once the icon that gives the user a way back
      // actually exists. Hiding a window with no tray would strand the app
      // with no way to restore or quit it.
      await windowManager.setPreventClose(true);
      return true;
    } catch (_) {
      // Unsupported, denied, or the native side is not up yet.
      windowManager.removeListener(this);
      _started = false;
      return false;
    }
  }

  /// Removes the tray icon and stops intercepting window close.
  Future<void> dispose() async {
    windowManager.removeListener(this);
    try {
      // Without the tray there is no way to come back from a hidden window,
      // so close must really close again once the icon is gone.
      await windowManager.setPreventClose(false);
    } catch (_) {
      // Tearing down on the way out must never throw.
    }
    try {
      final trayIcon = _trayIcon;
      final trayListenerId = _trayListenerId;
      if (trayIcon != null && trayListenerId != null) {
        trayIcon.removeListener(trayListenerId);
      }
      final menu = _menu;
      final menuListenerId = _menuListenerId;
      if (menu != null && menuListenerId != null) {
        menu.removeListener(menuListenerId);
      }
      trayIcon?.setVisible(false);
      trayIcon?.dispose();
      menu?.dispose();
    } catch (_) {
      // Native handles may already be gone; never throw while exiting.
    }
    _trayIcon = null;
    _menu = null;
    _openItem = null;
    _quitItem = null;
    _trayListenerId = null;
    _menuListenerId = null;
    _started = false;
  }

  /// Restores the window from the tray.
  Future<void> showWindow() async {
    try {
      if (!await windowManager.isVisible()) await windowManager.show();
      await windowManager.focus();
    } catch (_) {
      // A toast or tray click can race the window becoming ready.
    }
  }

  /// Ends the process, bypassing minimise-to-tray.
  ///
  /// The only path that really quits: the tray menu's Quit item and the
  /// "close normally" setting both route here.
  Future<void> quit() async {
    try {
      await windowManager.destroy();
    } catch (_) {
      exit(0);
    }
  }

  Menu? _buildMenu() {
    try {
      final menu = Menu.create();
      final openItem = MenuItem.createWithLabelAndType(
        'Open My Brief',
        MenuItemType.normal,
      );
      final quitItem = MenuItem.createWithLabelAndType(
        'Quit',
        MenuItemType.normal,
      );
      if (menu == null || openItem == null || quitItem == null) return null;

      _openItem = openItem;
      _quitItem = quitItem;
      menu
        ..addItem(openItem)
        ..addSeparator()
        ..addItem(quitItem);
      _menuListenerId = menu.addListener(_onMenuEvent);
      return menu;
    } catch (_) {
      return null;
    }
  }

  Future<void> _onTrayEvent(TrayIconEvent event) async {
    switch (event) {
      case TrayIconClickedEvent():
      case TrayIconDoubleClickedEvent():
        await showWindow();
      case TrayIconRightClickedEvent():
        try {
          _trayIcon?.openContextMenu();
        } catch (_) {
          // The menu could not be shown; the icon still works.
        }
    }
  }

  Future<void> _onMenuEvent(MenuEvent event) async {
    if (event is! MenuItemClickedEvent) return;
    // Items are matched by the native id assigned at creation, not by label,
    // so a translated or edited label cannot break the wiring.
    if (event.itemId == _openItem?.id) {
      await showWindow();
    } else if (event.itemId == _quitItem?.id) {
      await quit();
    }
  }

  /// WindowManagerListener: the user clicked the window's close button.
  ///
  /// Not awaited by the framework, so the decision it reads must already be
  /// available — hence the injected getter rather than a Future.
  @override
  void onWindowClose() async {
    try {
      if (minimizeToTray()) {
        await windowManager.hide();
      } else {
        await windowManager.destroy();
      }
    } catch (_) {
      // If neither hide nor destroy works there is nothing left to try.
    }
  }

  /// Loads the bundled tray icon, or null when it cannot be found.
  ///
  /// Windows tray icons must be real files, so the bundled asset is addressed
  /// on disk rather than read out of the asset bundle. Flutter places assets
  /// under `<exe dir>/data/flutter_assets` in both debug and release.
  static Image? _loadIcon() {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final candidates = [
        p.join(exeDir, 'data', 'flutter_assets', 'assets', 'icons',
            'tray_icon.ico'),
        // Running from the project root (e.g. an IDE launch configuration).
        p.join(Directory.current.path, 'assets', 'icons', 'tray_icon.ico'),
      ];
      for (final candidate in candidates) {
        if (!File(candidate).existsSync()) continue;
        return Image.fromFile(candidate);
      }
    } catch (_) {
      // A missing icon only costs the default Windows glyph.
    }
    return null;
  }
}
