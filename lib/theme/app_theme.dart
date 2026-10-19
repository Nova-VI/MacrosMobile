import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeManager {
  static final ValueNotifier<int> notifier = ValueNotifier(0);
  static const _defaultAccent = Color(0xFF10B981);
  static const _defaultBackground = Color(0xFF08080A);
  static const _defaultSurface = Color(0xFF16161C);
  static String? _activeUid;
  static int _revision = 0;
  static int _remoteRevision = 0;

  static Future<void> init() async {
    await activate(FirebaseAuth.instance.currentUser?.uid);
  }

  static Future<void> activate(String? uid) async {
    final revision = ++_revision;
    _activeUid = uid;
    AppColors.primary = _defaultAccent;
    AppColors.background = _defaultBackground;
    AppColors.surface = _defaultSurface;
    notifier.value++;
    if (uid == null) return;

    final prefs = await SharedPreferences.getInstance();
    if (revision != _revision || _activeUid != uid) return;
    for (final name in ['theme_accent', 'theme_bg', 'theme_surface']) {
      final legacy = prefs.getInt(name);
      if (legacy != null && !prefs.containsKey('${name}_$uid')) {
        await prefs.setInt('${name}_$uid', legacy);
      }
      if (legacy != null) await prefs.remove(name);
    }
    if (revision != _revision || _activeUid != uid) return;
    final acc = prefs.getInt('theme_accent_$uid');
    final bg = prefs.getInt('theme_bg_$uid');
    final sf = prefs.getInt('theme_surface_$uid');

    if (acc != null) AppColors.primary = Color(acc);
    if (bg != null) AppColors.background = Color(bg);
    if (sf != null) AppColors.surface = Color(sf);
    notifier.value++;
  }

  static Future<void> setAccent(Color color) async {
    final uid = _activeUid;
    if (uid == null) return;
    AppColors.primary = color;
    notifier.value++;
    HapticFeedback.lightImpact();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_accent_$uid', color.toARGB32());
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).collection('settings').doc('config').set({
        'app_accent_color': color.toARGB32(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  static Future<void> setBackground(Color bg, Color surface) async {
    final uid = _activeUid;
    if (uid == null) return;
    AppColors.background = bg;
    AppColors.surface = surface;
    notifier.value++;
    HapticFeedback.lightImpact();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_bg_$uid', bg.toARGB32());
    await prefs.setInt('theme_surface_$uid', surface.toARGB32());
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).collection('settings').doc('config').set({
        'app_background_color': bg.toARGB32(),
        'app_surface_color': surface.toARGB32(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  static Future<void> applyRemote(String uid, Map<String, dynamic> settings) async {
    if (_activeUid != uid) return;
    final revision = _revision;
    final remoteRevision = ++_remoteRevision;
    final accent = settings['app_accent_color'];
    final background = settings['app_background_color'];
    final surface = settings['app_surface_color'];
    if (accent is num) AppColors.primary = Color(accent.toInt());
    if (background is num) AppColors.background = Color(background.toInt());
    if (surface is num) AppColors.surface = Color(surface.toInt());
    if (accent is num || background is num || surface is num) notifier.value++;
    final prefs = await SharedPreferences.getInstance();
    if (_activeUid != uid || revision != _revision || remoteRevision != _remoteRevision) return;
    if (accent is num) await prefs.setInt('theme_accent_$uid', accent.toInt());
    if (background is num) await prefs.setInt('theme_bg_$uid', background.toInt());
    if (surface is num) await prefs.setInt('theme_surface_$uid', surface.toInt());
  }
}

class AppColors {
  static Color background = const Color(0xFF08080A);
  static Color surface = const Color(0xFF16161C);
  static Color primary = const Color(0xFF10B981);

  static const Color protein = Color.fromARGB(255, 51, 167, 47);
  static const Color carbs = Color.fromARGB(255, 57, 187, 252);
  static const Color fat = Color(0xFFEAB308);

  static const Color secondary = Color(0xFF3B82F6);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color surfaceHover = Color(0xFF22222B);
  static const Color border = Color(0xFF272732);
  static const Color textMain = Color(0xFFF9FAFB);
  static const Color textMuted = Color(0xFF9898A6);
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      primaryColor: AppColors.primary,
      splashFactory: InkSparkle.splashFactory,
      colorScheme: ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.surface,
        error: AppColors.danger,
        onPrimary: Colors.white,
        onSurface: AppColors.textMain,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: AppColors.border, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.textMain,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        iconTheme: IconThemeData(color: AppColors.textMain),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
        labelStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ),
      fontFamily: 'Roboto',
    );
  }
}
