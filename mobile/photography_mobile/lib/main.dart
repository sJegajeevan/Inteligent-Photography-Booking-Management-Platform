import 'package:flutter/material.dart';

import 'screens/auth/auth_gate.dart';
import 'theme/app_theme.dart';
import 'services/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance.load();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppSettings.instance,
    builder: (context, _) => MaterialApp(
    title: 'Photography AI',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: AppSettings.instance.themeMode,
    home: const AuthGate(),
  ));
}
