import 'package:flutter_test/flutter_test.dart';
import 'package:virxmagical/app/virxmagical_app.dart';

void main() {
  testWidgets('home displays VirxMagical identity and primary navigation', (
    tester,
  ) async {
    await tester.pumpWidget(const VirxMagicalApp());
    await tester.pumpAndSettle();

    expect(find.text('VirxMagical'), findsOneWidget);
    expect(find.text('اصنع واقعك\nبطريقتك.'), findsOneWidget);
    expect(find.text('الرئيسية'), findsOneWidget);
  });
}
