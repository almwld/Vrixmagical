import 'package:flutter_test/flutter_test.dart';
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

    test('calculates pinch relative to palm size', () {
      final points = List<Offset>.filled(21, Offset.zero);
      points[0] = const Offset(.5, .8);
      points[4] = const Offset(.49, .5);
      points[5] = const Offset(.4, .4);
      points[8] = const Offset(.51, .5);
      points[9] = const Offset(.5, .3);
      points[17] = const Offset(.6, .4);
      final ratio = HandGestureMath.pinchRatio(points, imageAspectRatio: 1);
      expect(ratio, isNotNull);
      expect(ratio!, lessThan(.30));
    });

    test('rejects invalid landmark geometry', () {
      expect(
        HandGestureMath.pinchRatio(const [Offset.zero], imageAspectRatio: 1),
        isNull,
      );
      expect(
        HandGestureMath.pinchRatio(List<Offset>.filled(21, Offset.zero), imageAspectRatio: 1),
        isNull,
      );
    });
  });

  group('PinchGesture', () {
    test('requires an open hand and sustained closing before pressing', () {
      final gesture = PinchGesture();
      expect(gesture.update(.2, 0), isNull); // not armed
      expect(gesture.update(.6, .01), isNull); // arm
      expect(gesture.update(.2, .02), isNull);
      expect(gesture.update(.2, .05), isNull);
      expect(gesture.update(.2, .10), PinchEvent.pressed);
      expect(gesture.isPinched, isTrue);
    });

    test('uses hysteresis and a release dwell', () {
      final gesture = PinchGesture();
      gesture.update(.6, 0);
      gesture.update(.2, .01);
      expect(gesture.update(.2, .09), PinchEvent.pressed);
      expect(gesture.update(.4, .10), isNull); // hysteresis band
      expect(gesture.isPinched, isTrue);
      expect(gesture.update(.6, .11), isNull);
      expect(gesture.update(.6, .15), isNull);
      expect(gesture.update(.6, .18), PinchEvent.released);
      expect(gesture.isPinched, isFalse);
    });

    test('lost tracking cancels a held pinch', () {
      final gesture = PinchGesture();
      gesture.update(.6, 0);
      gesture.update(.2, .01);
      expect(gesture.update(.2, .09), PinchEvent.pressed);
      expect(gesture.update(null, .10), PinchEvent.lost);
      expect(gesture.isPinched, isFalse);
    });
  });
}
