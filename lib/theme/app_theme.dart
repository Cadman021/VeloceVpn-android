import 'package:flutter/material.dart';

class AppColors {
  final Color bg, bgElevated, bgElevated2, border, text, textSecondary,
      textMuted, accent, accent2, accent3, success, warning, danger;

  const AppColors({
    required this.bg,
    required this.bgElevated,
    required this.bgElevated2,
    required this.border,
    required this.text,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accent2,
    required this.accent3,
    required this.success,
    required this.warning,
    required this.danger,
  });

  static const dark = AppColors(
    bg: Color(0xFF121316),
    bgElevated: Color(0xFF1C1E24),
    bgElevated2: Color(0xFF20232D),
    border: Color(0xFF2A2D37),
    text: Color(0xFFFFFFFF),
    textSecondary: Color(0xFF9AA0A6),
    textMuted: Color(0xFF5F6368),
    accent: Color(0xFF2563EB),
    accent2: Color(0xFF7C3AED),
    accent3: Color(0xFF06B6D4),
    success: Color(0xFF10B981),
    warning: Color(0xFFF59E0B),
    danger: Color(0xFFEF4444),
  );

  static const light = AppColors(
    bg: Color(0xFFF4F5F9),
    bgElevated: Color(0xFFFFFFFF),
    bgElevated2: Color(0xFFEEF0F6),
    border: Color(0xFFE1E3EC),
    text: Color(0xFF14161A),
    textSecondary: Color(0xFF676D7A),
    textMuted: Color(0xFF9198A6),
    accent: Color(0xFF2563EB),
    accent2: Color(0xFF7C3AED),
    accent3: Color(0xFF06B6D4),
    success: Color(0xFF059669),
    warning: Color(0xFFD97706),
    danger: Color(0xFFDC2626),
  );

  // همون گرادیانی که روی دسکتاپ/افزونه برای عنوان و دکمه‌ی connected استفاده شد
  static const brandGradient = LinearGradient(
    colors: [Color(0xFF7C3AED), Color(0xFF2563EB), Color(0xFF06B6D4)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

ThemeData buildAppTheme(AppColors c, Brightness brightness) {
  return ThemeData(
    brightness: brightness,
    scaffoldBackgroundColor: c.bg,
    fontFamily: 'Roboto',
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: Colors.white,
      secondary: c.accent2,
      onSecondary: Colors.white,
      error: c.danger,
      onError: Colors.white,
      surface: c.bgElevated,
      onSurface: c.text,
    ),
  );
}
