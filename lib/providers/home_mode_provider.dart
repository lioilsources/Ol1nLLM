import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Top-level app modes, switched via the segmented `ModeSwitcher` in each
/// screen's AppBar. Chat / Image Studio / OCR sit at the same level. The enum
/// order matches the IndexedStack children in `HomeShell`.
enum HomeMode { chat, studio, ocr }

final homeModeProvider = StateProvider<HomeMode>((ref) => HomeMode.chat);
