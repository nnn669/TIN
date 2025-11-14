import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/app_localizations.dart';

/// Desktop tray + window close behaviour controller.
///
/// - Manages system tray icon visibility and context menu
/// - Implements "minimize to tray on close" when enabled in settings
class DesktopTrayController with TrayListener, WindowListener {
  DesktopTrayController._();
  static final DesktopTrayController instance = DesktopTrayController._();

  bool _initialized = false;
  bool _isDesktop = false;
  bool _trayVisible = false;
  bool _showTraySetting = false;
  bool _minimizeToTrayOnClose = false;
  String _localeKey = '';

  /// Sync tray state from settings & current localization.
  /// Safe to call multiple times; initialization is performed lazily.
  Future<void> syncFromSettings(
    AppLocalizations l10n, {
    required bool showTray,
    required bool minimizeToTrayOnClose,
  }) async {
    if (kIsWeb) return;
    final isDesktop = defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
    if (!isDesktop) return;
    _isDesktop = true;

    if (!_initialized) {
      try {
        await windowManager.ensureInitialized();
      } catch (_) {}
      try {
        trayManager.addListener(this);
      } catch (_) {}
      try {
        windowManager.addListener(this);
      } catch (_) {}
      _initialized = true;
    }

    // Persist latest settings (enforce basic invariant in controller as well).
    _showTraySetting = showTray;
    _minimizeToTrayOnClose = showTray && minimizeToTrayOnClose;

    // Whether to intercept window close.
    final shouldPreventClose = _showTraySetting && _minimizeToTrayOnClose;
    try {
      await windowManager.setPreventClose(shouldPreventClose);
    } catch (_) {}

    // Handle tray icon visibility + localized menu.
    final newLocaleKey = l10n.localeName;
    final localeChanged = newLocaleKey != _localeKey;
    _localeKey = newLocaleKey;

    if (_showTraySetting) {
      if (!_trayVisible || localeChanged) {
        await _ensureTrayIconAndMenu(l10n);
        _trayVisible = true;
      }
    } else {
      if (_trayVisible) {
        try {
          await trayManager.destroy();
        } catch (_) {}
        _trayVisible = false;
      }
    }
  }

  Future<void> _ensureTrayIconAndMenu(AppLocalizations l10n) async {
    if (!_isDesktop) return;
    // Use platform-specific tray icons:
    // - Windows: .ico (recommended by tray_manager)
    // - macOS: dedicated PNG (assets/icon_mac.png)
    // - Linux/others: fallback PNG in assets/icons/
    final platform = defaultTargetPlatform;
    String iconPath;
    if (platform == TargetPlatform.windows) {
      iconPath = 'assets/app_icon.ico';
    } else if (platform == TargetPlatform.macOS) {
      iconPath = 'assets/icon_mac.png';
    } else {
      iconPath = 'assets/icons/kelivo.png';
    }
    try {
      await trayManager.setIcon(iconPath, isTemplate: true);
    } catch (_) {}
    try {
      await trayManager.setToolTip('Kelivo');
    } catch (_) {}
    try {
      final menu = Menu(items: [
        MenuItem(
          label: l10n.desktopTrayMenuShowWindow,
          onClick: (_) async => _showWindow(),
        ),
        MenuItem.separator(),
        MenuItem(
          label: l10n.desktopTrayMenuExit,
          onClick: (_) async => _exitApp(),
        ),
      ]);
      await trayManager.setContextMenu(menu);
    } catch (_) {}
  }

  Future<void> _showWindow() async {
    if (!_isDesktop) return;
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
  }

  Future<void> _exitApp() async {
    if (!_isDesktop) return;
    try {
      // Allow window to actually close, then close it.
      await windowManager.setPreventClose(false);
    } catch (_) {}
    try {
      await windowManager.close();
    } catch (_) {}
  }

  // ===== TrayListener =====

  @override
  void onTrayIconMouseDown() {
    // Left‑click: bring main window to front.
    if (!_isDesktop) return;
    _showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    // Right‑click:弹出菜单
    try {
      trayManager.popUpContextMenu(bringAppToFront: true);
    } catch (_) {}
  }

  // ===== WindowListener =====

  @override
  void onWindowClose() async {
    if (!_isDesktop) return;
    // Only intercept close when user enabled minimize-to-tray.
    final shouldIntercept = _showTraySetting && _minimizeToTrayOnClose;
    if (!shouldIntercept) return;
    try {
      final isPreventClose = await windowManager.isPreventClose();
      if (!isPreventClose) return;
      await windowManager.hide();
    } catch (_) {}
  }
}
