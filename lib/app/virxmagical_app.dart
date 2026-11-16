import 'package:material_ui/material_ui.dart';
import 'app_theme.dart';
import '../features/home/home_screen.dart';

class VirxMagicalApp extends StatelessWidget {
  const VirxMagicalApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'VirxMagical',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark,
    home: const HomeScreen(),
  );
}
