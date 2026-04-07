import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/constants/theme.dart';
import 'screens/chat_screen.dart';

class OllamaApp extends ConsumerWidget {
  const OllamaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Ol1nLLM',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const ChatScreen(),
    );
  }
}
