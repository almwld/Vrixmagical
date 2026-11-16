import 'package:flutter_test/flutter_test.dart';
import 'package:virxmagical/app/virxmagical_app.dart';

void main() {
  testWidgets('home displays VirxMagical identity and navigation', (tester) async {
    await tester.pumpWidget(const VirxMagicalApp());
    expect(find.text('VirxMagical'), findsOneWidget);
    expect(find.text('الاستوديو'), findsOneWidget);
  });
}
