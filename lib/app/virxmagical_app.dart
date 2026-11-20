import 'package:flutter_localizations/flutter_localizations.dart' as flutter_l10n;
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
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      flutter_l10n.GlobalWidgetsLocalizations.delegate,
    ],
    home: const Directionality(
      textDirection: TextDirection.rtl,
      child: HomeScreen(),
    ),
    builder: (context, child) => Directionality(
      textDirection: TextDirection.rtl,
      child: child ?? const SizedBox.shrink(),
    ),
  );
}
