import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatFluidMotionController extends ChangeNotifier {
  ChatFluidMotionController._() {
    _load();
  }

  static final ChatFluidMotionController instance =
      ChatFluidMotionController._();

  static const _preferenceKey = 'chat_fluid_motion_enabled_v1';

  bool _enabled = true;
  bool get enabled => _enabled;

  Future<void> _load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final enabled = preferences.getBool(_preferenceKey) ?? true;
      if (_enabled == enabled) return;
      _enabled = enabled;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setEnabled(bool enabled) async {
    if (_enabled == enabled) return;
    _enabled = enabled;
    notifyListeners();
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_preferenceKey, enabled);
    } catch (_) {}
  }
}