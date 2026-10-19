import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_tracker_mobile/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ThemeManager.activate(null);
  });

  test('remote app colors refresh and remain scoped to their account', () async {
    await ThemeManager.activate('alice');
    await ThemeManager.applyRemote('alice', {
      'app_accent_color': 0xFF8B5CF6,
      'app_background_color': 0xFF0A0F1C,
      'app_surface_color': 0xFF151C2C,
    });
    expect(AppColors.primary, const Color(0xFF8B5CF6));
    expect(AppColors.background, const Color(0xFF0A0F1C));

    await ThemeManager.activate('bob');
    expect(AppColors.primary, const Color(0xFF10B981));
    await ThemeManager.applyRemote('alice', {'app_accent_color': 0xFFF43F5E});
    expect(AppColors.primary, const Color(0xFF10B981));

    await ThemeManager.activate('alice');
    expect(AppColors.primary, const Color(0xFF8B5CF6));
    expect(AppColors.surface, const Color(0xFF151C2C));
  });

  test('legacy device color moves to the signed-in account', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_accent', 0xFFF97316);
    await ThemeManager.activate('alice');
    expect(AppColors.primary, const Color(0xFFF97316));
    expect(prefs.containsKey('theme_accent'), isFalse);
    expect(prefs.getInt('theme_accent_alice'), 0xFFF97316);
    await ThemeManager.activate('bob');
    expect(AppColors.primary, const Color(0xFF10B981));
  });
}
