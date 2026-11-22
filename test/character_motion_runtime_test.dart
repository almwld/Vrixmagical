import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:virxmagical/services/character_motion_runtime.dart';

void main() {
  group('CharacterMotionController', () {
    test('produces bounded breathing and blink channels', () {
      final motion = CharacterMotionController();
      var maximumBlink = 0.0;
      for (var i = 0; i < 60; i++) {
        final frame = motion.update(1 / 60);
        expect(frame.chestBreathScale, inInclusiveRange(0.988, 1.012));
        expect(frame.blinkWeight, inInclusiveRange(0.0, 1.0));
        if (frame.blinkWeight > maximumBlink) {
          maximumBlink = frame.blinkWeight;
        }
      }
      expect(maximumBlink, greaterThan(0.9));
    });

    test('smooths and clamps gaze targets', () {
      final motion = CharacterMotionController();
      final frame = motion.update(
        0.1,
        targetGazeYawRadians: 10,
        targetGazePitchRadians: -10,
      );
      expect(frame.gazeYawRadians, inInclusiveRange(0.0, 0.55));
      expect(frame.gazePitchRadians, inInclusiveRange(-0.35, 0.0));
    });

    test('rejects invalid time and gaze values', () {
      final motion = CharacterMotionController();
      expect(() => motion.update(-0.1), throwsArgumentError);
      expect(
        () => motion.update(0.01, targetGazeYawRadians: double.nan),
        throwsArgumentError,
      );
    });
  });

  group('TwoBoneIk', () {
    test('solves a reachable target while preserving bone lengths', () {
      final root = Vector3.zero();
      final target = Vector3(1, 1, 0);
      final pose = TwoBoneIk.solve(
        root: root,
        target: target,
        upperLength: 1,
        lowerLength: 1,
        poleDirection: Vector3(0, 0, 1),
      );
      expect((pose.joint - pose.root).length, closeTo(1, 1e-5));
      expect((pose.effector - pose.joint).length, closeTo(1, 1e-5));
      expect(pose.reachedTarget, isTrue);
    });

    test('clamps unreachable targets without producing non-finite joints', () {
      final pose = TwoBoneIk.solve(
        root: Vector3.zero(),
        target: Vector3(10, 0, 0),
        upperLength: 0.5,
        lowerLength: 0.5,
      );
      expect(pose.reachedTarget, isFalse);
      expect(pose.joint.x.isFinite, isTrue);
      expect(pose.joint.y.isFinite, isTrue);
      expect(pose.joint.z.isFinite, isTrue);
      expect((pose.effector - pose.root).length, lessThan(1.0));
    });

    test('rejects invalid bone lengths', () {
      expect(
        () => TwoBoneIk.solve(
          root: Vector3.zero(),
          target: Vector3(1, 0, 0),
          upperLength: 0,
          lowerLength: 1,
        ),
        throwsArgumentError,
      );
    });
  });
}
