import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

/// Immutable centreline for a generic, explicitly authored guided channel.
///
/// All points and clearances are expressed in the host object's local metres.
/// This geometry helper does not disable collision detection: callers must
/// retain the channel wall collider and apply a narrowly scoped pair policy.
class GuidedPathDefinition {
  GuidedPathDefinition({
    required String id,
    required Iterable<Vector3> controlPoints,
    required Iterable<double> clearanceRadii,
    this.entryTolerance = 0.02,
    this.exitTolerance = 0.02,
    this.permittedDirection = GuidedPathDirection.both,
  })  : id = id.trim(),
        controlPoints = List<Vector3>.unmodifiable(
          controlPoints.map(Vector3.copy),
        ),
        clearanceRadii = List<double>.unmodifiable(clearanceRadii) {
    if (this.id.isEmpty ||
        this.controlPoints.length < 2 ||
        this.clearanceRadii.length != this.controlPoints.length ||
        !entryTolerance.isFinite ||
        entryTolerance < 0 ||
        !exitTolerance.isFinite ||
        exitTolerance < 0) {
      throw const FormatException('Invalid guided-path definition.');
    }
    if (this.controlPoints.any(
          (point) =>
              !point.x.isFinite || !point.y.isFinite || !point.z.isFinite,
        ) ||
        this.clearanceRadii.any(
          (radius) => !radius.isFinite || radius <= 0,
        )) {
      throw const FormatException('Guided path contains invalid geometry.');
    }

    var length = 0.0;
    final cumulative = <double>[0];
    for (var i = 1; i < this.controlPoints.length; i++) {
      final segmentLength =
          this.controlPoints[i].distanceTo(this.controlPoints[i - 1]);
      if (segmentLength <= 1e-8) {
        throw const FormatException('Guided path has a zero-length segment.');
      }
      length += segmentLength;
      cumulative.add(length);
    }
    _cumulativeLengths = List<double>.unmodifiable(cumulative);
    totalLength = length;
  }

  final String id;
  final List<Vector3> controlPoints;
  final List<double> clearanceRadii;
  final double entryTolerance;
  final double exitTolerance;
  final GuidedPathDirection permittedDirection;
  late final List<double> _cumulativeLengths;
  late final double totalLength;

  /// Projects a point onto the closest centreline segment.
  GuidedPathProjection project(
    Vector3 point, {
    required double movingRadius,
    int travelDirection = 1,
  }) {
    if (!point.x.isFinite ||
        !point.y.isFinite ||
        !point.z.isFinite ||
        !movingRadius.isFinite ||
        movingRadius < 0 ||
        (travelDirection != -1 && travelDirection != 1)) {
      throw ArgumentError('Point and moving radius must be finite and valid.');
    }

    var bestDistanceSquared = double.infinity;
    var bestSegment = 0;
    var bestT = 0.0;
    var bestPoint = Vector3.zero();
    var bestTangent = Vector3.zero();

    for (var i = 0; i < controlPoints.length - 1; i++) {
      final start = controlPoints[i];
      final delta = controlPoints[i + 1] - start;
      final t = ((point - start).dot(delta) / delta.length2)
          .clamp(0.0, 1.0)
          .toDouble();
      final closest = start + delta * t;
      final distanceSquared = point.distanceToSquared(closest);
      if (distanceSquared < bestDistanceSquared) {
        bestDistanceSquared = distanceSquared;
        bestSegment = i;
        bestT = t;
        bestPoint = closest;
        bestTangent = delta.normalized();
      }
    }

    final startRadius = clearanceRadii[bestSegment];
    final endRadius = clearanceRadii[bestSegment + 1];
    final clearance = startRadius + (endRadius - startRadius) * bestT;
    final arcLength = _cumulativeLengths[bestSegment] +
        (controlPoints[bestSegment + 1]
                .distanceTo(controlPoints[bestSegment]) *
            bestT);
    final normalizedProgress = (arcLength / totalLength).clamp(0.0, 1.0);
    final lateralDistance = math.sqrt(bestDistanceSquared);

    final inEntryZone = arcLength <= entryTolerance;
    final inExitZone = totalLength - arcLength <= exitTolerance;
    final fits = lateralDistance + movingRadius <= clearance;
    final directionAllowed = permittedDirection == GuidedPathDirection.both ||
        (permittedDirection == GuidedPathDirection.forward && travelDirection > 0) ||
        (permittedDirection == GuidedPathDirection.reverse && travelDirection < 0);
    final phase = !fits
        ? GuidedPathPhase.outside
        : !directionAllowed
            ? GuidedPathPhase.disallowedDirection
            : inEntryZone
                ? GuidedPathPhase.entry
                : inExitZone
                    ? GuidedPathPhase.exit
                    : GuidedPathPhase.inside;

    return GuidedPathProjection(
      pathId: id,
      segmentIndex: bestSegment,
      progress: normalizedProgress,
      closestPoint: bestPoint,
      tangent: bestTangent,
      lateralDistance: lateralDistance,
      clearanceRadius: clearance,
      movingRadius: movingRadius,
      hasClearance: fits,
      phase: phase,
    );
  }
}

enum GuidedPathDirection { both, forward, reverse }

enum GuidedPathPhase { outside, entry, inside, exit, disallowedDirection }

class GuidedPathProjection {
  GuidedPathProjection({
    required this.pathId,
    required this.segmentIndex,
    required this.progress,
    required Vector3 closestPoint,
    required Vector3 tangent,
    required this.lateralDistance,
    required this.clearanceRadius,
    required this.movingRadius,
    required this.hasClearance,
    required this.phase,
  })  : closestPoint = Vector3.copy(closestPoint),
        tangent = Vector3.copy(tangent);

  final String pathId;
  final int segmentIndex;
  final double progress;
  final Vector3 closestPoint;
  final Vector3 tangent;
  final double lateralDistance;
  final double clearanceRadius;
  final double movingRadius;
  final bool hasClearance;
  final GuidedPathPhase phase;
}
