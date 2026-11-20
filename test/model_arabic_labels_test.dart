import 'package:flutter_test/flutter_test.dart';
import 'package:virxmagical/services/model_arabic_labels.dart';

void main() {
  group('ModelArabicLabels', () {
    test('translates known scene nodes', () {
      expect(ModelArabicLabels.translate('Duck'), 'بطة');
      expect(ModelArabicLabels.translate('LeftArm'), 'الذراع الأيسر');
      expect(ModelArabicLabels.translate('Material'), 'الخامة');
    });
    test('preserves unknown labels without inventing a translation', () {
      expect(ModelArabicLabels.translate('CustomRigNode_42'), 'CustomRigNode_42');
      expect(ModelArabicLabels.displayName('UnknownModel'), 'مجسم مستورد · UnknownModel');
    });
  });
}
