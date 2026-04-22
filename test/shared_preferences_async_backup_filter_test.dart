import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/services/backup/data_sync.dart' as backup_sync;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPreferencesAsync backup filter', () {
    test('snapshot excludes local-only chat font scale', () async {
      SharedPreferences.setMockInitialValues({
        'display_chat_font_scale_v1': 1.3,
        'display_auto_scroll_enabled_v1': false,
      });

      final prefs = await backup_sync.SharedPreferencesAsync.instance;
      final snapshot = await prefs.snapshot();

      expect(snapshot.containsKey('display_chat_font_scale_v1'), isFalse);
      expect(snapshot['display_auto_scroll_enabled_v1'], isFalse);
    });

    test(
      'restore ignores chat font scale but restores synced settings',
      () async {
        SharedPreferences.setMockInitialValues({
          'display_chat_font_scale_v1': 1.15,
        });

        final prefs = await backup_sync.SharedPreferencesAsync.instance;
        await prefs.restore({
          'display_chat_font_scale_v1': 1.4,
          'display_auto_scroll_enabled_v1': false,
        });

        final rawPrefs = await SharedPreferences.getInstance();
        expect(rawPrefs.getDouble('display_chat_font_scale_v1'), 1.15);
        expect(rawPrefs.getBool('display_auto_scroll_enabled_v1'), isFalse);
      },
    );

    test('restoreSingle ignores old backup chat font scale entries', () async {
      SharedPreferences.setMockInitialValues({
        'display_chat_font_scale_v1': 0.95,
      });

      final prefs = await backup_sync.SharedPreferencesAsync.instance;
      await prefs.restoreSingle('display_chat_font_scale_v1', 1.5);

      final rawPrefs = await SharedPreferences.getInstance();
      expect(rawPrefs.getDouble('display_chat_font_scale_v1'), 0.95);
    });
  });
}
