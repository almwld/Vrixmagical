import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:virxmagical/features/settings/settings_screen.dart';

void main() {
  testWidgets('settings categories open their internal pages', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    expect(find.text('إعدادات المحرك'), findsOneWidget);
    await tester.tap(find.text('الواجهة والعرض'));
    await tester.pumpAndSettle();
    expect(find.text('واجهة عربية من اليمين إلى اليسار'), findsOneWidget);
  });
}
