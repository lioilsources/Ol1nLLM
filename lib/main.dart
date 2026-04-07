import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Catch all Flutter framework errors (including in release mode).
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };
  // Catch async errors outside the Flutter framework (e.g. in platform channels).
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Unhandled error: $error\n$stack');
    return true;
  };
  await Hive.initFlutter();
  runApp(const ProviderScope(child: OllamaApp()));
}
