import 'package:flutter_test/flutter_test.dart';
import 'package:virxmagical/app/virxmagical_app.dart';

void main() {
  testWidgets('home displays VirxMagical identity and primary navigation', (
    tester,
  ) async {
    await tester.pumpWidget(const VirxMagicalApp());
    // The home screen contains animated scroll and navigation widgets; do not
    // wait for the entire tree to become idle.
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('VirxMagical'), findsOneWidget);
    expect(find.text('اصنع واقعك\nبطريقتك.'), findsOneWidget);
    expect(find.text('الرئيسية'), findsOneWidget);
  });
}
