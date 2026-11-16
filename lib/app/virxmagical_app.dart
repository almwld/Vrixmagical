import 'package:flutter/material.dart';
import '../features/home/home_screen.dart';

class VirxMagicalApp extends StatelessWidget {
  const VirxMagicalApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'VirxMagical',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF080D16),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF42E8D5),
        brightness: Brightness.dark,
        surface: const Color(0xFF111B2A),
      ),
      useMaterial3: true,
    ),
    home: const HomeScreen(),
  );
}
