import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:virxmagical/features/hand/hand_gesture_math.dart';

void main() {
  group('HandGestureMath', () {
    test('recognizes a pinch inside the normalized threshold', () {
      expect(HandGestureMath.isPinching(const Offset(.50, .50), const Offset(.53, .52)), isTrue);
    });
    test('does not recognize separated fingertips as a pinch', () {
      expect(HandGestureMath.isPinching(const Offset(.20, .20), const Offset(.50, .50)), isFalse);
    });
    test('supports a custom threshold', () {
      expect(HandGestureMath.isPinching(const Offset(.20, .20), const Offset(.30, .20), threshold: .12), isTrue);
    });
  });
}
