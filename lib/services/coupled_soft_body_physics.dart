import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import 'package:vrix_soft_body/vrix_soft_body.dart';
import 'physics_scene_service.dart';

/// Couples one XPBD deformable mesh to Jolt through a kinematic convex proxy.
///
/// Direction A (Jolt -> XPBD): Jolt contact begin/stay events become unilateral
/// per-vertex XPBD contact constraints.
///
/// Direction B (XPBD -> Jolt): XPBD reaction forces are integrated over the
/// fixed step and applied as impulses at the original world-space contact point
/// to dynamic Jolt bodies. Static/kinematic bodies correctly receive no impulse.
///
/// The proxy follows the XPBD centre of mass, so Jolt detects external contacts
/// without treating the deformable mesh as a second, independently simulated
/// rigid body. Use a PhysicsSceneService(reportContactStay: true).
class CoupledSoftBodyPhysics {
  CoupledSoftBodyPhysics({
    required this.scene,
    required this.engine,
    required this.softBody,
    required this.mesh,
    required this.proxyBodyId,
    required Matrix4 initialTransform,
    this.contactFriction = 0.5,
    this.contactCompliance = 0,
    this.maxContactDistance = 0.08,
  }) : _initialTransform = Matrix4.copy(initialTransform) {
    mesh.validate();
    if (!scene.reportContactStay) {
      throw ArgumentError(
        'Bidirectional XPBD coupling requires PhysicsSceneService(reportContactStay: true).',
      );
    }
    if (!contactFriction.isFinite || contactFriction < 0 ||
        !contactCompliance.isFinite || contactCompliance < 0 ||
        !maxContactDistance.isFinite || maxContactDistance <= 0) {
      throw ArgumentError('Invalid deformable contact parameters.');
    }
    final localVertices = <Vector3>[
      for (var i = 0; i < mesh.vertexCount; i++)
        Vector3(
          mesh.positions[i * 3],
          mesh.positions[i * 3 + 1],
          mesh.positions[i * 3 + 2],
        ),
    ];
    scene.addKinematicConvexHull(
      id: proxyBodyId,
      worldTransform: _initialTransform,
      vertices: localVertices,
      friction: contactFriction,
    );
    _initialCentroid = _centroid(mesh.positions);
  }

  final PhysicsSceneService scene;
  final VrixSoftBodyFfiEngine engine;
  final SoftBodyHandle softBody;
  final SoftBodyMeshData mesh;
  final String proxyBodyId;
  final double contactFriction;
  final double contactCompliance;
  final double maxContactDistance;
  final Matrix4 _initialTransform;
  late final Vector3 _initialCentroid;
  final Map<String, _ActiveContact> _contacts = <String, _ActiveContact>{};
  bool _disposed = false;
  int _coupledSteps = 0;

  int get coupledSteps => _coupledSteps;
  int get activeContactCount => _contacts.length;

  /// Advances one frame in a deterministic order. Jolt detects contacts first;
  /// XPBD solves those constraints second; XPBD reactions feed Jolt on its next
  /// native step. This one-step force feedback delay avoids mutating Jolt while
  /// its contact/event buffers are being drained.
  int advance(double deltaSeconds) {
    _ensureActive();
    if (!deltaSeconds.isFinite || deltaSeconds <= 0) {
      throw ArgumentError.value(deltaSeconds, 'deltaSeconds');
    }

    final before = engine.readState(softBody);
    _moveProxyToSoftBodyCentre(before.positions, deltaSeconds);
    final rigidSteps = scene.advance(deltaSeconds);
    _consumeJoltContacts(deltaSeconds);
    engine.step(deltaSeconds);
    _applyXpbdReactions(deltaSeconds);
    _coupledSteps++;
    return rigidSteps;
  }

  void _moveProxyToSoftBodyCentre(List<double> positions, double dt) {
    final centre = _centroid(positions);
    final displacement = centre - _initialCentroid;
    final target = Matrix4.copy(_initialTransform);
    final origin = target.getTranslation();
    target.setTranslation(origin + displacement);
    scene.moveKinematic(proxyBodyId, target, deltaSeconds: dt);
  }

  void _consumeJoltContacts(double deltaSeconds) {
    final events = scene.drainEvents();
    // A contact-end event arrives after Jolt's step, while XPBD still holds
    // the reaction accumulated during the previous soft-body step. Flush it
    // before clearing the vertex constraint or its rigid-body reaction is lost.
    final hasProxyContactEnd = events.any(
      (event) =>
          event.isContactEnd &&
          (event.bodyA == proxyBodyId || event.bodyB == proxyBodyId),
    );
    if (hasProxyContactEnd) _applyXpbdReactions(deltaSeconds);

    for (final event in events) {
      if (event.bodyA != proxyBodyId && event.bodyB != proxyBodyId) continue;
      final otherBody = event.bodyA == proxyBodyId ? event.bodyB : event.bodyA;
      if (otherBody == null || otherBody == proxyBodyId) continue;
      final key = _contactKey(otherBody, event.point);

      if (event.isContactEnd) {
        final previous = _contacts.remove(key);
        if (previous != null) {
          engine.clearContact(body: softBody, vertexIndex: previous.vertexIndex);
        }
        continue;
      }
      if (!event.isContactBegin && !event.isContactStay) continue;

      final proxyIsA = event.bodyA == proxyBodyId;
      // Jolt's event normal is oriented A -> B. XPBD expects the normal from
      // the rigid surface toward the deformable free space.
      final worldNormal = Vector3.copy(event.normal);
      if (proxyIsA) worldNormal.negate();
      final transform = scene.bodyWorldTransform(proxyBodyId);
      final inverse = Matrix4.inverted(transform);
      final localPoint = inverse.transform3(Vector3.copy(event.point));
      final localNormalTip = inverse.transform3(
        Vector3.copy(event.point)..add(worldNormal),
      );
      final localNormal = localNormalTip - localPoint;
      if (localNormal.length2 <= 1e-12) continue;
      localNormal.normalize();

      final state = engine.readState(softBody);
      final nearest = _nearestVertex(state.positions, localPoint);
      if (nearest.distance > maxContactDistance) continue;
      final previous = _contacts[key];
      if (previous != null && previous.vertexIndex != nearest.index) {
        engine.clearContact(body: softBody, vertexIndex: previous.vertexIndex);
      }
      engine.setContact(
        body: softBody,
        vertexIndex: nearest.index,
        point: <double>[localPoint.x, localPoint.y, localPoint.z],
        normal: <double>[localNormal.x, localNormal.y, localNormal.z],
        friction: contactFriction,
        compliance: contactCompliance,
      );
      _contacts[key] = _ActiveContact(
        otherBodyId: otherBody,
        vertexIndex: nearest.index,
        worldPoint: Vector3.copy(event.point),
      );
    }
  }

  void _applyXpbdReactions(double dt) {
    if (_contacts.isEmpty) {
      // Drain the native accumulator even when no rigid body is currently in
      // contact, preventing stale reactions from being applied on a later hit.
      engine.readReactionForces(softBody);
      return;
    }
    final reactions = engine.readReactionForces(softBody);
    final transform = scene.bodyWorldTransform(proxyBodyId);
    final grouped = <String, _ReactionAccumulator>{};
    for (final contact in _contacts.values) {
      if (!scene.isDynamicBody(contact.otherBodyId)) continue;
      final offset = contact.vertexIndex * 3;
      final localForce = Vector3(
        reactions[offset],
        reactions[offset + 1],
        reactions[offset + 2],
      );
      if (localForce.length2 <= 1e-12) continue;
      final worldOrigin = transform.transform3(Vector3.zero());
      final worldTip = transform.transform3(localForce);
      final worldForce = worldTip - worldOrigin;
      final bucket = grouped.putIfAbsent(
        contact.otherBodyId,
        () => _ReactionAccumulator(),
      );
      bucket.impulse.add(worldForce * dt);
      bucket.weightedPoint.add(contact.worldPoint * worldForce.length);
      bucket.weight += worldForce.length;
    }
    for (final entry in grouped.entries) {
      final bucket = entry.value;
      if (bucket.impulse.length2 <= 1e-14) continue;
      final point = bucket.weight > 1e-9
          ? bucket.weightedPoint / bucket.weight
          : Vector3.zero();
      scene.applyImpulseAtPoint(entry.key, bucket.impulse, point);
    }
  }

  _NearestVertex _nearestVertex(List<double> positions, Vector3 point) {
    var bestIndex = -1;
    var bestDistanceSquared = double.infinity;
    for (var i = 0; i < mesh.vertexCount; i++) {
      final dx = positions[i * 3] - point.x;
      final dy = positions[i * 3 + 1] - point.y;
      final dz = positions[i * 3 + 2] - point.z;
      final distanceSquared = dx * dx + dy * dy + dz * dz;
      if (distanceSquared < bestDistanceSquared) {
        bestDistanceSquared = distanceSquared;
        bestIndex = i;
      }
    }
    return _NearestVertex(bestIndex, math.sqrt(bestDistanceSquared));
  }

  Vector3 _centroid(List<double> positions) {
    if (positions.length != mesh.vertexCount * 3) {
      throw StateError('XPBD state does not match the coupled mesh vertex count.');
    }
    final result = Vector3.zero();
    for (var i = 0; i < mesh.vertexCount; i++) {
      result.x += positions[i * 3];
      result.y += positions[i * 3 + 1];
      result.z += positions[i * 3 + 2];
    }
    return result / mesh.vertexCount.toDouble();
  }

  String _contactKey(String bodyId, Vector3 point) => bodyId;

  void _ensureActive() {
    if (_disposed) throw StateError('Coupled soft-body physics has been disposed.');
  }

  void dispose({bool removeProxy = true}) {
    if (_disposed) return;
    for (final contact in _contacts.values) {
      engine.clearContact(body: softBody, vertexIndex: contact.vertexIndex);
    }
    _contacts.clear();
    if (removeProxy) scene.removeBody(proxyBodyId);
    _disposed = true;
  }
}

class _ActiveContact {
  const _ActiveContact({
    required this.otherBodyId,
    required this.vertexIndex,
    required this.worldPoint,
  });

  final String otherBodyId;
  final int vertexIndex;
  final Vector3 worldPoint;
}

class _NearestVertex {
  const _NearestVertex(this.index, this.distance);
  final int index;
  final double distance;
}

class _ReactionAccumulator {
  final Vector3 impulse = Vector3.zero();
  final Vector3 weightedPoint = Vector3.zero();
  double weight = 0;
}
