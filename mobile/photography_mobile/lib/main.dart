import 'package:flutter/material.dart';

import 'screens/studio/studio_list_screen.dart';
import 'theme/app_theme.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Photography AI',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: const StudioListScreen(),
  );
}
