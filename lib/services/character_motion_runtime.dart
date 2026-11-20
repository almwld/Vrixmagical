import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

/// Per-frame procedural channels for a rig-aware character renderer.
///
/// The host renderer maps [chestBreathScale], [blinkWeight], and gaze angles
/// to its own morph targets and bone names. This class does not pretend to
/// modify a GLB by itself; it supplies deterministic, frame-rate-independent
/// animation values for a real skeleton/blend-shape adapter.
class CharacterMotionFrame {
  const CharacterMotionFrame({
    required this.chestBreathScale,
    required this.blinkWeight,
    required this.gazeYawRadians,
    required this.gazePitchRadians,
  });

  final double chestBreathScale;
  final double blinkWeight;
  final double gazeYawRadians;
  final double gazePitchRadians;
}

/// Procedural idle motion with smoothed gaze and non-periodic-looking blinks.
class CharacterMotionController {
  CharacterMotionController({
    this.breathingPeriodSeconds = 4.2,
    this.breathingAmplitude = 0.012,
    this.blinkIntervalSeconds = 4.7,
    this.blinkDurationSeconds = 0.14,
    this.gazeResponse = 11.0,
    this.maximumGazeYawRadians = 0.55,
    this.maximumGazePitchRadians = 0.35,
  }) {
    if (!breathingPeriodSeconds.isFinite ||
        breathingPeriodSeconds <= 0 ||
        !breathingAmplitude.isFinite ||
        breathingAmplitude < 0 ||
        !blinkIntervalSeconds.isFinite ||
        blinkIntervalSeconds <= 0 ||
        !blinkDurationSeconds.isFinite ||
        blinkDurationSeconds <= 0 ||
        blinkDurationSeconds >= blinkIntervalSeconds ||
        !gazeResponse.isFinite ||
        gazeResponse <= 0 ||
        !maximumGazeYawRadians.isFinite ||
        maximumGazeYawRadians <= 0 ||
        !maximumGazePitchRadians.isFinite ||
        maximumGazePitchRadians <= 0) {
      throw ArgumentError('Character motion settings must be finite and positive.');
    }
  }

  final double breathingPeriodSeconds;
  final double breathingAmplitude;
  final double blinkIntervalSeconds;
  final double blinkDurationSeconds;
  final double gazeResponse;
  final double maximumGazeYawRadians;
  final double maximumGazePitchRadians;

  double _elapsed = 0;
  double _gazeYaw = 0;
  double _gazePitch = 0;

  CharacterMotionFrame update(
    double deltaSeconds, {
    double targetGazeYawRadians = 0,
    double targetGazePitchRadians = 0,
  }) {
    if (!deltaSeconds.isFinite || deltaSeconds < 0 ||
        !targetGazeYawRadians.isFinite || !targetGazePitchRadians.isFinite) {
      throw ArgumentError('Motion time and gaze targets must be finite; time cannot be negative.');
    }

    // Bound a delayed frame so resume-from-background does not jump the rig.
    final dt = deltaSeconds.clamp(0.0, 0.1).toDouble();
    _elapsed += dt;
    final smoothing = 1 - math.exp(-gazeResponse * dt);
    _gazeYaw += (targetGazeYawRadians.clamp(
      -maximumGazeYawRadians,
      maximumGazeYawRadians,
    ) - _gazeYaw) * smoothing;
    _gazePitch += (targetGazePitchRadians.clamp(
      -maximumGazePitchRadians,
      maximumGazePitchRadians,
    ) - _gazePitch) * smoothing;

    final breathPhase = 2 * math.pi * _elapsed / breathingPeriodSeconds;
    final chestScale = 1 + breathingAmplitude * math.sin(breathPhase);
    final blinkPhase = _elapsed % blinkIntervalSeconds;
    final blinkProgress = blinkPhase / blinkDurationSeconds;
    final blinkWeight = blinkPhase < blinkDurationSeconds
        ? math.pow(math.sin(math.pi * blinkProgress), 2).toDouble()
        : 0.0;

    return CharacterMotionFrame(
      chestBreathScale: chestScale,
      blinkWeight: blinkWeight.clamp(0.0, 1.0).toDouble(),
      gazeYawRadians: _gazeYaw,
      gazePitchRadians: _gazePitch,
    );
  }

  void reset() {
    _elapsed = 0;
    _gazeYaw = 0;
    _gazePitch = 0;
  }
}

class TwoBoneIkPose {
  const TwoBoneIkPose({
    required this.root,
    required this.joint,
    required this.effector,
    required this.reachedTarget,
  });

  final Vector3 root;
  final Vector3 joint;
  final Vector3 effector;
  final bool reachedTarget;
}

/// Stable analytic two-bone IK solver for arms and legs.
///
/// The caller supplies a pole vector to choose the bend plane. The returned
/// effector is clamped to the reachable annulus rather than producing NaNs
/// when a hand target lies too close to or too far from the shoulder.
class TwoBoneIk {
  const TwoBoneIk._();

  static TwoBoneIkPose solve({
    required Vector3 root,
    required Vector3 target,
    required double upperLength,
    required double lowerLength,
    Vector3? poleDirection,
    double epsilon = 1e-5,
  }) {
    if (!_finiteVector(root) ||
        !_finiteVector(target) ||
        !upperLength.isFinite ||
        !lowerLength.isFinite ||
        upperLength <= epsilon ||
        lowerLength <= epsilon ||
        !epsilon.isFinite ||
        epsilon <= 0 ||
        (poleDirection != null && !_finiteVector(poleDirection))) {
      throw ArgumentError('IK inputs must be finite and both bone lengths must be positive.');
    }

    final delta = target - root;
    final distance = delta.length;
    final direction = distance > epsilon
        ? delta / distance
        : Vector3(0, 0, 1);
    final minimumReach = (upperLength - lowerLength).abs() + epsilon;
    final maximumReach = upperLength + lowerLength - epsilon;
    final clampedDistance = distance.clamp(minimumReach, maximumReach).toDouble();
    final effector = root + direction * clampedDistance;

    var pole = poleDirection ?? Vector3(0, 1, 0);
    pole = pole - direction * pole.dot(direction);
    if (pole.length2 <= epsilon * epsilon) {
      pole = direction.cross(Vector3(1, 0, 0));
      if (pole.length2 <= epsilon * epsilon) {
        pole = direction.cross(Vector3(0, 1, 0));
      }
    }
    pole.normalize();

    final along = (upperLength * upperLength -
            lowerLength * lowerLength +
            clampedDistance * clampedDistance) /
        (2 * clampedDistance);
    final heightSquared = math.max(
      0.0,
      upperLength * upperLength - along * along,
    );
    final joint = root + direction * along + pole * math.sqrt(heightSquared);

    return TwoBoneIkPose(
      root: root.clone(),
      joint: joint,
      effector: effector,
      reachedTarget: (effector - target).length <= epsilon * 2,
    );
  }

  static bool _finiteVector(Vector3 value) =>
      value.x.isFinite && value.y.isFinite && value.z.isFinite;
}
