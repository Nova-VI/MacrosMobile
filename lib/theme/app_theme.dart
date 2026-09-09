import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeManager {
  static final ValueNotifier<int> notifier = ValueNotifier(0);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final acc = prefs.getInt('theme_accent');
    final bg = prefs.getInt('theme_bg');
    final sf = prefs.getInt('theme_surface');

    if (acc != null) AppColors.primary = Color(acc);
    if (bg != null) AppColors.background = Color(bg);
    if (sf != null) AppColors.surface = Color(sf);
  }

  static void setAccent(Color color) {
    AppColors.primary = color;
    notifier.value++;
    HapticFeedback.lightImpact();

    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt('theme_accent', color.value);
    });
  }

  static void setBackground(Color bg, Color surface) {
    AppColors.background = bg;
    AppColors.surface = surface;
    notifier.value++;
    HapticFeedback.lightImpact();

    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt('theme_bg', bg.value);
      prefs.setInt('theme_surface', surface.value);
    });
  }
}

class AppColors {
  // Mutable Theme Colors
  static Color background = const Color(0xFF08080A);
  static Color surface = const Color(0xFF16161C);
  static Color primary = const Color(0xFF10B981);

  // Dedicated Semantic Macro Colors (Decoupled from UI Accents)
  static const Color protein = Color.fromARGB(255, 51, 167, 47); // Forest Green
  static const Color carbs = Color.fromARGB(255, 57, 187, 252);   //  Cyan
  static const Color fat = Color(0xFFEAB308);     // Golden Yellow

  // Structural & Status Colors
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