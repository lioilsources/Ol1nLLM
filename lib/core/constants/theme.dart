import 'package:flutter/material.dart';

class AppTheme {
  static const background = Color(0xFF0D0D0D);
  static const surface = Color(0xFF1A1A1A);
  static const surfaceAlt = Color(0xFF212121);
  static const userBubble = Color(0xFF2A2A2A);
  static const aiBubble = Color(0xFF161616);
  static const accent = Color(0xFF10A37F);
  static const textPrimary = Color(0xFFECECEC);
  static const textSecondary = Color(0xFF8E8E8E);
  static const drawerWidth = 280.0;

  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.dark(
          surface: surface,
          primary: accent,
        ),
        drawerTheme: const DrawerThemeData(
          backgroundColor: surface,
          width: drawerWidth,
        ),
        dividerColor: Colors.white12,
        appBarTheme: const AppBarTheme(
          backgroundColor: background,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          titleTextStyle: TextStyle(
            color: textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          iconTheme: IconThemeData(color: textPrimary),
        ),
      );
}
