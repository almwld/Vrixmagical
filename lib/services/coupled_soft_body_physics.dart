import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import 'package:vrix_soft_body/vrix_soft_body.dart';
import 'physics_scene_service.dart';
import '../domain/soft_body_contact_policy.dart';
import '../domain/soft_body_reaction_mapper.dart';

/// Couples one XPBD deformable mesh to Jolt through a kinematic convex proxy.
///
/// Direction A (Jolt -> XPBD): a non-resolving Jolt sensor proxy is queried
/// after each rigid step. Its overlap normals/points become unilateral XPBD
/// per-vertex contact constraints.
///
/// Direction B (XPBD -> Jolt): XPBD reaction forces are integrated over the
/// fixed step and applied once as impulses at world-space contact points to
/// dynamic Jolt bodies. The sensor proxy deliberately prevents Jolt from also
/// resolving the same rigid contact, avoiding double collision response.
///
/// The proxy follows the XPBD centre of mass; its convex hull is a broadphase
/// approximation, while XPBD remains the deformable state owner.
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
    if (!contactFriction.isFinite || contactFriction < 0 ||
        !contactCompliance.isFinite || contactCompliance < 0 ||
        !maxContactDistance.isFinite || maxContactDistance <= 0) {
      throw ArgumentError('Invalid deformable contact parameters.');
    }
    final localVertices = _buildBoundedProxyVertices();
    scene.addKinematicConvexHull(
      id: proxyBodyId,
      worldTransform: _initialTransform,
      vertices: localVertices,
      friction: contactFriction,
      sensor: true,
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
  final Map<int, _ActiveContact> _contacts = <int, _ActiveContact>{};
  bool _disposed = false;
  int _coupledSteps = 0;
  final Vector3 _lastAppliedReactionImpulse = Vector3.zero();
  final Vector3 _lastContactNormalWorld = Vector3.zero();
  int _lastAppliedReactionCount = 0;

  int get coupledSteps => _coupledSteps;
  int get activeContactCount => _contacts.length;
  int get lastAppliedReactionCount => _lastAppliedReactionCount;
  Vector3 get lastAppliedReactionImpulse =>
      Vector3.copy(_lastAppliedReactionImpulse);
  Vector3 get lastContactNormalWorld => Vector3.copy(_lastContactNormalWorld);

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
    _refreshContactsFromJoltOverlaps();
    engine.step(deltaSeconds);
    // Convert averaged native reaction forces using the time XPBD actually
    // simulated, not the unbounded wall-clock frame delta. The native fixed-step
    // accumulator may clamp or defer part of a frame.
    _applyXpbdReactions(engine.simulatedDeltaSeconds(softBody));
    _coupledSteps++;
    return rigidSteps;
  }

  /// Jolt's convex proxy is only a broadphase approximation. Keep it
  /// bounded for mobile even when a scan contains tens of thousands of XPBD
  /// vertices. The AABB corners preserve conservative spatial coverage while
  /// deterministic surface samples retain some curvature for contact queries.
  List<Vector3> _buildBoundedProxyVertices() {
    const maximumProxyVertices = 4096;
    if (mesh.vertexCount <= maximumProxyVertices) {
      return List<Vector3>.generate(
        mesh.vertexCount,
        (index) => Vector3(
          mesh.positions[index * 3],
          mesh.positions[index * 3 + 1],
          mesh.positions[index * 3 + 2],
        ),
        growable: false,
      );
    }

    var minX = double.infinity;
    var minY = double.infinity;
    var minZ = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    var maxZ = double.negativeInfinity;
    for (var i = 0; i < mesh.vertexCount; i++) {
      final x = mesh.positions[i * 3];
      final y = mesh.positions[i * 3 + 1];
      final z = mesh.positions[i * 3 + 2];
      minX = math.min(minX, x);
      minY = math.min(minY, y);
      minZ = math.min(minZ, z);
      maxX = math.max(maxX, x);
      maxY = math.max(maxY, y);
      maxZ = math.max(maxZ, z);
    }

    final vertices = <Vector3>[
      Vector3(minX, minY, minZ),
      Vector3(minX, minY, maxZ),
      Vector3(minX, maxY, minZ),
      Vector3(minX, maxY, maxZ),
      Vector3(maxX, minY, minZ),
      Vector3(maxX, minY, maxZ),
      Vector3(maxX, maxY, minZ),
      Vector3(maxX, maxY, maxZ),
    ];
    final sampleBudget = maximumProxyVertices - vertices.length;
    final stride = (mesh.vertexCount / sampleBudget).ceil();
    for (var i = 0; i < mesh.vertexCount && vertices.length < maximumProxyVertices; i += stride) {
      vertices.add(Vector3(
        mesh.positions[i * 3],
        mesh.positions[i * 3 + 1],
        mesh.positions[i * 3 + 2],
      ));
    }
    return vertices;
  }

  void _moveProxyToSoftBodyCentre(List<double> positions, double dt) {
    final centre = _centroid(positions);
    final displacement = centre - _initialCentroid;
    final target = Matrix4.copy(_initialTransform);
    // XPBD positions are object-local. Rotate the local centroid displacement
    // into world space before moving the Jolt proxy; adding it directly would
    // drift whenever the scanned object is initially rotated.
    final origin = target.getTranslation();
    final worldDisplacement =
        _initialTransform.transform3(displacement) -
        _initialTransform.transform3(Vector3.zero());
    target.setTranslation(origin + worldDisplacement);
    scene.moveKinematic(proxyBodyId, target, deltaSeconds: dt);
  }

  void _refreshContactsFromJoltOverlaps() {
    // Sensor begin/end events are drained for bounded native event memory.
    // Persistent contact geometry is refreshed by a shape-overlap query each
    // frame because Jolt intentionally does not solve or emit contact-stay
    // constraints for sensors.
    scene.drainEvents();
    final transform = scene.bodyWorldTransform(proxyBodyId);
    final inverse = Matrix4.inverted(transform);
    final state = engine.readState(softBody);
    final hits = scene.overlapBody(proxyBodyId, includeSensors: false)
      ..sort((a, b) => (a.bodyId ?? '').compareTo(b.bodyId ?? ''));
    final nextContacts = <int, _ActiveContact>{};
    _lastContactNormalWorld.setZero();

    for (final hit in hits) {
      final otherBody = hit.bodyId;
      if (otherBody == null || otherBody == proxyBodyId) continue;

      final localPoint = inverse.transform3(Vector3.copy(hit.point));
      // JJ_Hit.normal is the target surface normal facing the query shape.
      // Since the query shape is the soft-body proxy, this already points from
      // the rigid surface toward the deformable body; do not flip it by A/B.
      final localNormalTip = inverse.transform3(
        Vector3.copy(hit.point)..add(hit.normal),
      );
      final localNormal = localNormalTip - localPoint;
      if (localNormal.length2 <= 1e-12) continue;
      localNormal.normalize();

      final nearest = _nearestVertex(state.positions, localPoint);
      if (nearest.index < 0 || nearest.distance > maxContactDistance) continue;

      final currentContact = nextContacts[nearest.index];
      if (!SoftBodyContactPolicy.shouldAcceptContact(
        currentBodyId: currentContact?.otherBodyId,
        incomingBodyId: otherBody,
      )) {
        continue;
      }
      nextContacts[nearest.index] = _ActiveContact(
        otherBodyId: otherBody,
        vertexIndex: nearest.index,
        worldPoint: Vector3.copy(hit.point),
        localPoint: localPoint,
        localNormal: localNormal,
      );
      _lastContactNormalWorld.setFrom(hit.normal);
    }

    // The native XPBD contract stores one contact per vertex. Clear contacts
    // that disappeared or whose deterministic rigid-body owner changed.
    for (final entry in _contacts.entries) {
      final next = nextContacts[entry.key];
      if (next == null || next.otherBodyId != entry.value.otherBodyId) {
        engine.clearContact(body: softBody, vertexIndex: entry.key);
      }
    }

    for (final contact in nextContacts.values) {
      engine.setContact(
        body: softBody,
        vertexIndex: contact.vertexIndex,
        point: <double>[
          contact.localPoint.x,
          contact.localPoint.y,
          contact.localPoint.z,
        ],
        normal: <double>[
          contact.localNormal.x,
          contact.localNormal.y,
          contact.localNormal.z,
        ],
        friction: contactFriction,
        compliance: contactCompliance,
      );
    }
    _contacts
      ..clear()
      ..addAll(nextContacts);
  }

  void _applyXpbdReactions(double deltaSeconds) {
    final reactions = engine.readReactionForces(softBody);
    _lastAppliedReactionImpulse.setZero();
    _lastAppliedReactionCount = 0;
    if (_contacts.isEmpty || deltaSeconds <= 0) return;

    final impulses = SoftBodyReactionMapper.map(
      packedForces: reactions,
      contacts: _contacts.values.map(
        (contact) => SoftBodyReactionContact(
          rigidBodyId: contact.otherBodyId,
          vertexIndex: contact.vertexIndex,
          worldPoint: contact.worldPoint,
        ),
      ),
      worldTransform: scene.bodyWorldTransform(proxyBodyId),
      deltaSeconds: deltaSeconds,
      isDynamicBody: scene.isDynamicBody,
    );

    // Keep every contact's point of application. Aggregating by body can
    // erase a pure torque couple when its linear impulses cancel.
    for (final impulse in impulses) {
      scene.applyImpulseAtPoint(
        impulse.rigidBodyId,
        impulse.impulse,
        impulse.worldPoint,
      );
      _lastAppliedReactionImpulse.add(impulse.impulse);
      _lastAppliedReactionCount++;
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
    required this.localPoint,
    required this.localNormal,
  });

  final String otherBodyId;
  final int vertexIndex;
  final Vector3 worldPoint;
  final Vector3 localPoint;
  final Vector3 localNormal;
}

class _NearestVertex {
  const _NearestVertex(this.index, this.distance);
  final int index;
  final double distance;
}
