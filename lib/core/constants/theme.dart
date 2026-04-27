import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class AppTheme {
  static const background = Color(0xFF0D0D0D);
  static const surface = Color(0xFF1A1A1A);
  static const surfaceAlt = Color(0xFF212121);
  static const userBubble = Color(0xFF2A2A2A);
  static const aiBubble = Color(0xFF1E1E1E);
  static const accent = Color(0xFF10A37F);
  static const textPrimary = Color(0xFFECECEC);
  static const textSecondary = Color(0xFF8E8E8E);
  static const drawerWidth = 280.0;

  static MarkdownStyleSheet markdownStyle(BuildContext context) {
    const base = TextStyle(
      color: textPrimary,
      fontSize: 15,
      height: 1.5,
    );
    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: base,
      strong: base.copyWith(fontWeight: FontWeight.w700),
      em: base.copyWith(fontStyle: FontStyle.italic),
      del: base.copyWith(decoration: TextDecoration.lineThrough),
      h1: base.copyWith(fontSize: 22, fontWeight: FontWeight.w700),
      h2: base.copyWith(fontSize: 19, fontWeight: FontWeight.w700),
      h3: base.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
      code: base.copyWith(
        fontFamily: 'monospace',
        fontSize: 13,
        color: const Color(0xFFE5C07B),
        backgroundColor: surface,
      ),
      codeblockDecoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(8),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      blockquoteDecoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: accent, width: 3),
        ),
      ),
      blockquotePadding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
      blockquote: base.copyWith(color: textSecondary),
      a: base.copyWith(color: accent, decoration: TextDecoration.underline),
      listBullet: base,
    );
  }

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
