import 'package:vector_math/vector_math_64.dart';

import 'package:vrix_soft_body/vrix_soft_body.dart';
import 'ar_session_hand_perception.dart';

/// Small adapter over the native XPBD point-target API. Keeping this seam
/// independent from FFI makes the interaction mapping testable without loading
/// the Android native library in Flutter unit tests.
abstract interface class XpbdPointTargetDriver {
  SoftBodyState readState();
  void setPointTarget({
    required int vertexIndex,
    required List<double> targetObjectPosition,
    double compliance,
  });
  void clearPointTarget({required int vertexIndex});
}

/// Adapts the application's native XPBD engine to [XpbdPointTargetDriver].
class NativeXpbdPointTargetDriver implements XpbdPointTargetDriver {
  NativeXpbdPointTargetDriver({
    required this.engine,
    required this.body,
  });

  final VrixSoftBodyFfiEngine engine;
  final SoftBodyHandle body;

  @override
  SoftBodyState readState() => engine.readState(body);

  @override
  void setPointTarget({
    required int vertexIndex,
    required List<double> targetObjectPosition,
    double compliance = 0,
  }) {
    engine.setPointTarget(
      body: body,
      vertexIndex: vertexIndex,
      targetObjectPosition: targetObjectPosition,
      compliance: compliance,
    );
  }

  @override
  void clearPointTarget({required int vertexIndex}) {
    engine.clearPointTarget(body: body, vertexIndex: vertexIndex);
  }
}

/// Maps pinch-held AR hand tips to local XPBD vertex targets.
///
/// The camera/depth pipeline supplies world-space fingertip coordinates. This
/// bridge transforms them into the deformable object's local metres, selects
/// the nearest current XPBD vertex, and updates a persistent point constraint.
/// When the pinch releases or tracking disappears, the constraint is cleared.
class ArHandXpbdBridge {
  ArHandXpbdBridge({
    required this.driver,
    this.compliance = 0.0001,
    this.maximumTargetDistanceMeters = 0.12,
  }) {
    if (!compliance.isFinite ||
        compliance < 0 ||
        !maximumTargetDistanceMeters.isFinite ||
        maximumTargetDistanceMeters <= 0) {
      throw ArgumentError('XPBD hand interaction limits must be finite and valid.');
    }
  }

  final XpbdPointTargetDriver driver;
  final double compliance;
  final double maximumTargetDistanceMeters;
  final Map<String, int> _activeTargets = <String, int>{};

  Map<String, int> get activeTargets => Map.unmodifiable(_activeTargets);

  void update({
    required ArHandObservation observation,
    required Matrix4 worldFromObject,
  }) {
    final inverse = Matrix4.copy(worldFromObject);
    inverse.invert();
    if (inverse.storage.any((value) => !value.isFinite)) {
      throw ArgumentError('Soft-body world transform must be invertible and finite.');
    }

    final state = driver.readState();
    final claimedVertices = <int>{};
    final updatedHands = <String>{};

    for (final hand in observation.hands) {
      final key = hand.handedness;
      if (key.isEmpty || key == 'Unknown') continue;
      if (!hand.isPinching || hand.indexTipWorld == null) continue;

      final localTarget = inverse.transform3(hand.indexTipWorld!.clone());
      if (!_isFinite(localTarget)) continue;

      var vertexIndex = _activeTargets[key];
      if (vertexIndex == null || vertexIndex >= state.positions.length ~/ 3) {
        vertexIndex = _nearestVertex(
          state.positions,
          localTarget,
          claimedVertices,
        );
        if (vertexIndex == null) continue;
        _activeTargets[key] = vertexIndex;
      }
      claimedVertices.add(vertexIndex);
      driver.setPointTarget(
        vertexIndex: vertexIndex,
        targetObjectPosition: [
          localTarget.x,
          localTarget.y,
          localTarget.z,
        ],
        compliance: compliance,
      );
      updatedHands.add(key);
    }

    // Keep a constraint only when this frame supplied a valid, finite target.
    // A detected pinch with invalid depth/coordinates must not leave the last
    // native target active indefinitely.
    for (final key in _activeTargets.keys.toList(growable: false)) {
      if (updatedHands.contains(key)) continue;
      final vertex = _activeTargets.remove(key);
      if (vertex != null) driver.clearPointTarget(vertexIndex: vertex);
    }
  }

  void clear() {
    for (final vertex in _activeTargets.values.toSet()) {
      driver.clearPointTarget(vertexIndex: vertex);
    }
    _activeTargets.clear();
  }

  int? _nearestVertex(
    List<double> positions,
    Vector3 target,
    Set<int> reserved,
  ) {
    if (positions.isEmpty || positions.length % 3 != 0) return null;
    var nearest = -1;
    var nearestDistanceSquared = maximumTargetDistanceMeters *
        maximumTargetDistanceMeters;
    for (var i = 0; i < positions.length ~/ 3; i++) {
      if (reserved.contains(i)) continue;
      final dx = positions[i * 3] - target.x;
      final dy = positions[i * 3 + 1] - target.y;
      final dz = positions[i * 3 + 2] - target.z;
      final distanceSquared = dx * dx + dy * dy + dz * dz;
      if (distanceSquared <= nearestDistanceSquared) {
        nearestDistanceSquared = distanceSquared;
        nearest = i;
      }
    }
    return nearest < 0 ? null : nearest;
  }

  bool _isFinite(Vector3 point) =>
      point.x.isFinite && point.y.isFinite && point.z.isFinite;
}
