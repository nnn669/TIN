import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter_background/flutter_background.dart';

/// Simple manager for enabling/disabling background execution on Android.
/// All calls are no-ops on non-Android platforms.
class AndroidBackgroundManager {
  static bool _initialized = false;
  static Future<bool>? _initializing;

  /// Initialize the plugin once and request needed permissions.
  /// Concurrent callers share the same initialization to avoid duplicate
  /// plugin calls and repeated permission/system prompts.
  static Future<bool> ensureInitialized({
    String? notificationTitle,
    String? notificationText,
  }) {
    if (!Platform.isAndroid) return Future<bool>.value(false);
    if (_initialized) return Future<bool>.value(true);
    final pending = _initializing;
    if (pending != null) return pending;

    final future = _initialize(
      notificationTitle: notificationTitle,
      notificationText: notificationText,
    );
    _initializing = future;
    return future.whenComplete(() {
      if (identical(_initializing, future)) _initializing = null;
    });
  }

  static Future<bool> _initialize({
    String? notificationTitle,
    String? notificationText,
  }) async {
    try {
      final androidConfig = FlutterBackgroundAndroidConfig(
        notificationTitle: notificationTitle ?? 'Kelivo is running',
        notificationText:
            notificationText ?? 'Keeping chat generation alive in background',
        notificationImportance: AndroidNotificationImportance.normal,
        notificationIcon: const AndroidResource(
          name: 'ic_launcher',
          defType: 'mipmap',
        ),
      );
      final ok = await FlutterBackground.initialize(
        androidConfig: androidConfig,
      );
      _initialized = ok;
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Enable/disable background execution. Requires [ensureInitialized] to have run.
  static Future<void> setEnabled(bool enable) async {
    if (!Platform.isAndroid) return;
    try {
      try {
        final current = FlutterBackground.isBackgroundExecutionEnabled;
        if (current == enable) return;
      } catch (_) {}

      if (enable) {
        if (!_initialized) {
          final ready = await ensureInitialized();
          if (!ready) return;
        }
        await FlutterBackground.enableBackgroundExecution();
      } else {
        try {
          await FlutterBackground.disableBackgroundExecution();
        } catch (_) {}
      }
    } catch (_) {
      // Best effort only.
    }
  }

  /// Convenience to query whether background execution is currently enabled.
  static Future<bool> isEnabled() async {
    if (!Platform.isAndroid) return false;
    try {
      return FlutterBackground.isBackgroundExecutionEnabled;
    } catch (_) {
      return false;
    }
  }
}
