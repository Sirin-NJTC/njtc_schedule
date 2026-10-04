/// 应用主题 —— 美观的配色与字体。
library;

import 'package:flutter/material.dart';

/// 应用主题配置。
class AppTheme {
  AppTheme._();

  /// 主题色板
  static const Color primary = Color(0xFF5B6BF0); // 靛蓝主色
  static const Color secondary = Color(0xFF8B5CF6); // 紫色
  static const Color accent = Color(0xFF10B981); // 翡翠绿
  static const Color background = Color(0xFFF5F6FA); // 浅灰背景
  static const Color card = Colors.white;
  static const Color textPrimary = Color(0xFF1F2937);
  static const Color textSecondary = Color(0xFF6B7280);

  /// 课程卡片配色（按课程循环选择，柔和一致）。
  static const List<Color> courseColors = [
    Color(0xFF6366F1), // 靛蓝
    Color(0xFF8B5CF6), // 紫
    Color(0xFFEC4899), // 粉
    Color(0xFFF59E0B), // 琥珀
    Color(0xFF10B981), // 绿
    Color(0xFF06B6D4), // 青
    Color(0xFF3B82F6), // 蓝
    Color(0xFFEF4444), // 红
  ];

  /// 根据课程名稳定取色。
  static Color colorForCourse(String name) {
    if (name.isEmpty) return courseColors[0];
    final hash = name.codeUnits.fold<int>(0, (a, b) => a + b);
    return courseColors[hash % courseColors.length];
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        foregroundColor: textPrimary,
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
