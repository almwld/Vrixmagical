import 'dart:ffi';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:just_jolt/ffi.dart' as jolt;
import 'package:vector_math/vector_math_64.dart';

enum PhysicsJointKind { fixed, point, hinge, slider, distance, sixDof }

enum PhysicsJointMotor { off, velocity, position }

class PhysicsContactEvent {
  const PhysicsContactEvent({
    required this.type,
    required this.bodyA,
    required this.bodyB,
    required this.depth,
    required this.normal,
    required this.point,
  });

  final int type;
  final String? bodyA;
  final String? bodyB;
  final double depth;
  final Vector3 normal;
  final Vector3 point;

  bool get isContactBegin => type == jolt.JJ_EVENT_CONTACT_BEGIN;
  bool get isContactStay => type == jolt.JJ_EVENT_CONTACT_STAY;
  bool get isContactEnd => type == jolt.JJ_EVENT_CONTACT_END;
  bool get isSensorBegin => type == jolt.JJ_EVENT_SENSOR_BEGIN;
  bool get isSensorEnd => type == jolt.JJ_EVENT_SENSOR_END;
}

class PhysicsRaycastHit {
  const PhysicsRaycastHit({
    required this.bodyId,
    required this.point,
    required this.normal,
    required this.fraction,
    required this.depth,
  });

  final String? bodyId;
  final Vector3 point;
  final Vector3 normal;
  final double fraction;
  final double depth;
}

enum _ShapeKind { box, sphere, capsule }

class _ShapeSpec {
  const _ShapeSpec(this.kind, this.values);

  final _ShapeKind kind;
  final List<double> values;
}

class _BodyRecord {
  _BodyRecord({
    required this.id,
    required this.shape,
    required this.motionType,
    required this.transform,
    required this.friction,
    required this.restitution,
    required this.gravityFactor,
    required this.mass,
    required this.layer,
    required this.sensor,
    required this.continuous,
    required this.linearDamping,
    required this.angularDamping,
    required this.linearVelocity,
  });

  final String id;
  final _ShapeSpec shape;
  final int motionType;
  Matrix4 transform;
  final double friction;
  final double restitution;
  final double gravityFactor;
  final double mass;
  final int layer;
  final bool sensor;
  final bool continuous;
  final double linearDamping;
  final double angularDamping;
  Vector3 linearVelocity;
  int handle = 0;
}

class _JointRecord {
  const _JointRecord({
    required this.id,
    required this.handle,
    required this.bodyA,
    required this.bodyB,
  });

  final String id;
  final int handle;
  final String bodyA;
  final String? bodyB;
}

/// Production-oriented Jolt Physics 5.6 world adapter.
///
/// Jolt owns broadphase/narrowphase collision detection, rigid-body integration,
/// sleeping, continuous collision, contact/sensor events, ray queries and
/// constraints. All positions are metres and all rotations are unit quaternions.
class PhysicsSceneService {
  PhysicsSceneService({
    this.fixedStepSeconds = 1 / 60,
    this.maxSubSteps = 5,
    this.collisionSteps = 2,
    this.maxBodies = 2048,
  }) {
    if (!fixedStepSeconds.isFinite ||
        fixedStepSeconds <= 0 ||
        maxSubSteps < 1 ||
        collisionSteps < 1 ||
        maxBodies < 1) {
      throw ArgumentError('Physics world limits must be positive and finite.');
    }

    final reason = jolt.Jolt.start();
    if (reason != null) {
      throw UnsupportedError('Jolt is unavailable: $reason');
    }
    if (!jolt.jj_init(-1)) {
      throw StateError('Jolt native initialization failed.');
    }

    using((arena) {
      final settings = arena<jolt.JJ_WorldSettings>();
      settings.ref
        ..gravity[0] = 0
        ..gravity[1] = -9.81
        ..gravity[2] = 0
        ..maxBodies = maxBodies
        ..maxBodyPairs = math.max(8192, maxBodies * 16)
        ..maxContactConstraints = math.max(4096, maxBodies * 8)
        ..tempAllocatorBytes = 8 * 1024 * 1024
        ..reportActivation = true
        ..reportContactStay = false
        ..restitutionCombine = jolt.JJ_COMBINE_DEFAULT;
      for (var layer = 0; layer < jolt.JJ_LAYER_COUNT; layer++) {
        settings.ref.collides[layer] = 0xFFFF;
      }
      _world = jolt.jj_world_create(settings);
    });
    if (_world == 0) {
      throw StateError('Jolt could not allocate a physics world.');
    }

    final version = jolt.jj_version();
    engineLabel =
        'Jolt ${(version >> 16) & 0xff}.${(version >> 8) & 0xff}.${version & 0xff}';
  }

  final double fixedStepSeconds;
  final int maxSubSteps;
  final int collisionSteps;
  final int maxBodies;
  late final int _world;
  late final String engineLabel;
  final Map<String, _BodyRecord> _bodies = <String, _BodyRecord>{};
  final Map<int, String> _bodyIdsByHandle = <int, String>{};
  final Map<String, _JointRecord> _joints = <String, _JointRecord>{};
  double _accumulator = 0;
  bool _disposed = false;

  int get bodyCount => _bodies.length;
  int get jointCount => _joints.length;
  bool get isDisposed => _disposed;

  void addStaticBox({
    required String id,
    required Matrix4 worldTransform,
    required Vector3 halfExtents,
    double friction = 0.8,
    double restitution = 0,
  }) {
    _addBody(
      id: id,
      shape: _boxSpec(halfExtents),
      motionType: jolt.JJ_MOTION_STATIC,
      worldTransform: worldTransform,
      friction: friction,
      restitution: restitution,
      gravityFactor: 0,
      mass: 0,
      layer: 0,
      sensor: false,
      continuous: false,
    );
  }

  void addDynamicBox({
    required String id,
    required Matrix4 worldTransform,
    required Vector3 halfExtents,
    Vector3? linearVelocity,
    double friction = 0.55,
    double restitution = 0.08,
    double mass = 0,
    bool continuous = true,
  }) {
    _addBody(
      id: id,
      shape: _boxSpec(halfExtents),
      motionType: jolt.JJ_MOTION_DYNAMIC,
      worldTransform: worldTransform,
      friction: friction,
      restitution: restitution,
      gravityFactor: 1,
      mass: mass,
      layer: 1,
      sensor: false,
      continuous: continuous,
      linearVelocity: linearVelocity,
    );
  }

  void addDynamicSphere({
    required String id,
    required Matrix4 worldTransform,
    required double radius,
    double friction = 0.55,
    double restitution = 0.08,
    double mass = 0,
    bool continuous = true,
  }) {
    _validatePositive(radius, 'radius');
    _addBody(
      id: id,
      shape: _ShapeSpec(_ShapeKind.sphere, <double>[radius]),
      motionType: jolt.JJ_MOTION_DYNAMIC,
      worldTransform: worldTransform,
      friction: friction,
      restitution: restitution,
      gravityFactor: 1,
      mass: mass,
      layer: 1,
      sensor: false,
      continuous: continuous,
    );
  }

  void addDynamicCapsule({
    required String id,
    required Matrix4 worldTransform,
    required double radius,
    required double halfHeight,
    double friction = 0.65,
    double restitution = 0.02,
    double mass = 0,
    bool continuous = true,
  }) {
    _validatePositive(radius, 'radius');
    _validatePositive(halfHeight, 'halfHeight');
    _addBody(
      id: id,
      shape: _ShapeSpec(_ShapeKind.capsule, <double>[halfHeight, radius]),
      motionType: jolt.JJ_MOTION_DYNAMIC,
      worldTransform: worldTransform,
      friction: friction,
      restitution: restitution,
      gravityFactor: 1,
      mass: mass,
      layer: 1,
      sensor: false,
      continuous: continuous,
    );
  }

  void addSensorBox({
    required String id,
    required Matrix4 worldTransform,
    required Vector3 halfExtents,
    bool dynamic = false,
  }) {
    _addBody(
      id: id,
      shape: _boxSpec(halfExtents),
      motionType: dynamic ? jolt.JJ_MOTION_DYNAMIC : jolt.JJ_MOTION_STATIC,
      worldTransform: worldTransform,
      friction: 0,
      restitution: 0,
      gravityFactor: dynamic ? 1 : 0,
      mass: 0,
      layer: 2,
      sensor: true,
      continuous: false,
    );
  }

  _ShapeSpec _boxSpec(Vector3 halfExtents) {
    if (!_isFiniteVector(halfExtents) ||
        halfExtents.x <= 0 ||
        halfExtents.y <= 0 ||
        halfExtents.z <= 0) {
      throw ArgumentError.value(halfExtents, 'halfExtents');
    }
    return _ShapeSpec(
      _ShapeKind.box,
      <double>[halfExtents.x, halfExtents.y, halfExtents.z],
    );
  }

  void _addBody({
    required String id,
    required _ShapeSpec shape,
    required int motionType,
    required Matrix4 worldTransform,
    required double friction,
    required double restitution,
    required double gravityFactor,
    required double mass,
    required int layer,
    required bool sensor,
    required bool continuous,
    Vector3? linearVelocity,
    double linearDamping = 0.02,
    double angularDamping = 0.05,
  }) {
    _ensureAvailable();
    _validateId(id);
    if (_bodies.containsKey(id)) {
      throw StateError('Physics body already exists: $id');
    }
    if (_bodies.length >= maxBodies) {
      throw StateError('Physics world body capacity ($maxBodies) reached.');
    }
    _validateMaterial(friction, restitution);
    if (!gravityFactor.isFinite ||
        gravityFactor < 0 ||
        !mass.isFinite ||
        mass < 0 ||
        layer < 0 ||
        layer >= jolt.JJ_LAYER_COUNT ||
        !linearDamping.isFinite ||
        linearDamping < 0 ||
        !angularDamping.isFinite ||
        angularDamping < 0) {
      throw ArgumentError('Invalid body physical properties.');
    }
    final velocity = linearVelocity ?? Vector3.zero();
    if (!_isFiniteVector(velocity)) {
      throw ArgumentError.value(linearVelocity, 'linearVelocity');
    }
    _toPose(worldTransform);
    final record = _BodyRecord(
      id: id,
      shape: shape,
      motionType: motionType,
      transform: Matrix4.copy(worldTransform),
      friction: friction,
      restitution: restitution,
      gravityFactor: gravityFactor,
      mass: mass,
      layer: layer,
      sensor: sensor,
      continuous: continuous,
      linearDamping: linearDamping,
      angularDamping: angularDamping,
      linearVelocity: Vector3.copy(velocity),
    );
    record.handle = _createNativeBody(record);
    _bodies[id] = record;
    _bodyIdsByHandle[record.handle] = id;
  }

  int _createNativeBody(_BodyRecord record) {
    return using((arena) {
      final shape = _createShape(arena, record.shape);
      if (shape.address == 0) {
        throw StateError('Jolt could not create collider for ${record.id}.');
      }
      try {
        final pose = _toPose(record.transform);
        final settings = arena<jolt.JJ_BodySettings>();
        settings.ref
          ..motionType = record.motionType
          ..friction = record.friction
          ..restitution = record.restitution
          ..gravityFactor = record.gravityFactor
          ..mass = record.mass
          ..allowSleeping = true
          ..layer = record.layer
          ..isSensor = record.sensor
          ..motionQuality = record.continuous ? 1 : 0
          ..linearDamping = record.linearDamping
          ..angularDamping = record.angularDamping;
        for (var i = 0; i < 3; i++) {
          settings.ref.position[i] = pose.position[i];
          settings.ref.linearVelocity[i] = record.linearVelocity[i];
        }
        for (var i = 0; i < 4; i++) {
          settings.ref.rotation[i] = pose.rotation[i];
        }
        final handle = jolt.jj_body_create(_world, shape, settings);
        if (handle == 0) {
          throw StateError('Jolt rejected body ${record.id}.');
        }
        return handle;
      } finally {
        jolt.jj_shape_release(shape.cast<Void>());
      }
    });
  }

  Pointer<jolt.JPH_Shape> _createShape(Arena arena, _ShapeSpec spec) {
    switch (spec.kind) {
      case _ShapeKind.box:
        final half = arena<jolt.JPH_Vec3>();
        half.ref
          ..x = spec.values[0]
          ..y = spec.values[1]
          ..z = spec.values[2];
        final convexRadius = math.min(
          0.05,
          math.min(spec.values[0], math.min(spec.values[1], spec.values[2])) *
              0.2,
        );
        return jolt.JPH_BoxShape_Create(half, convexRadius).cast();
      case _ShapeKind.sphere:
        return jolt.JPH_SphereShape_Create(spec.values[0]).cast();
      case _ShapeKind.capsule:
        return jolt.JPH_CapsuleShape_Create(
          spec.values[0],
          spec.values[1],
        ).cast();
    }
  }

  /// Runs bounded fixed-step simulation. Returns the number of native steps.
  int advance(double frameDeltaSeconds) {
    _ensureAvailable();
    if (!frameDeltaSeconds.isFinite || frameDeltaSeconds < 0) {
      throw ArgumentError.value(frameDeltaSeconds, 'frameDeltaSeconds');
    }
    _accumulator += math.min(
      frameDeltaSeconds,
      fixedStepSeconds * maxSubSteps,
    );
    var steps = 0;
    while (_accumulator >= fixedStepSeconds && steps < maxSubSteps) {
      final result = jolt.jj_world_step(_world, fixedStepSeconds, collisionSteps);
      if (result < 0) {
        throw StateError('Jolt physics world became invalid during simulation.');
      }
      if (result != 0) {
        throw StateError('Jolt simulation reported update error flags: $result.');
      }
      _accumulator -= fixedStepSeconds;
      steps++;
    }
    if (steps == maxSubSteps && _accumulator >= fixedStepSeconds) {
      _accumulator %= fixedStepSeconds;
    }
    return steps;
  }

  /// Reads one body's pose from Jolt. Pose indices are xyz + quaternion xyzw.
  Matrix4 bodyWorldTransform(String id) {
    _ensureAvailable();
    final record = _bodies[id];
    if (record == null) throw StateError('Unknown physics body: $id');
    return using((arena) {
      final handles = arena<Int64>(1)..[0] = record.handle;
      final values = arena<Float>(jolt.JJ_TRANSFORM_FLOATS);
      final count = jolt.jj_get_transforms(_world, handles, 1, values);
      if (count != 1) throw StateError('Jolt failed to read body ${record.id}.');
      return _matrixFromPose(values, 0);
    });
  }

  /// Efficiently reads only awake bodies and bodies that just went to sleep.
  /// This avoids sending unchanged transforms through the AR platform channel.
  Map<String, Matrix4> activeBodyTransforms() {
    _ensureAvailable();
    if (_bodies.isEmpty) return <String, Matrix4>{};
    return using((arena) {
      var capacity = _bodies.length;
      var handles = arena<Int64>(capacity);
      var values = arena<Float>(capacity * jolt.JJ_TRANSFORM_FLOATS);
      var count = jolt.jj_get_active_transforms(
        _world,
        handles,
        values,
        capacity,
      );
      if (count < 0) {
        capacity = -count;
        handles = arena<Int64>(capacity);
        values = arena<Float>(capacity * jolt.JJ_TRANSFORM_FLOATS);
        count = jolt.jj_get_active_transforms(
          _world,
          handles,
          values,
          capacity,
        );
      }
      if (count < 0) {
        throw StateError('Jolt active-transform buffer could not be sized.');
      }
      final result = <String, Matrix4>{};
      for (var i = 0; i < count; i++) {
        final id = _bodyIdsByHandle[handles[i]];
        if (id == null) continue;
        result[id] = _matrixFromPose(values, i * jolt.JJ_TRANSFORM_FLOATS);
      }
      return result;
    });
  }

  void setBodyWorldTransform(String id, Matrix4 transform) {
    _ensureAvailable();
    final record = _bodies[id];
    if (record == null) return;
    if (_joints.values.any((joint) => joint.bodyA == id || joint.bodyB == id)) {
      throw StateError('Cannot teleport a body while it is connected to a joint.');
    }
    _toPose(transform);
    final previousHandle = record.handle;
    final updated = Matrix4.copy(transform);
    final replacement = _BodyRecord(
      id: record.id,
      shape: record.shape,
      motionType: record.motionType,
      transform: updated,
      friction: record.friction,
      restitution: record.restitution,
      gravityFactor: record.gravityFactor,
      mass: record.mass,
      layer: record.layer,
      sensor: record.sensor,
      continuous: record.continuous,
      linearDamping: record.linearDamping,
      angularDamping: record.angularDamping,
      linearVelocity: Vector3.zero(),
    );
    final nextHandle = _createNativeBody(replacement);
    jolt.jj_body_destroy(previousHandle);
    _bodyIdsByHandle.remove(previousHandle);
    record
      ..handle = nextHandle
      ..transform = updated
      ..linearVelocity = Vector3.zero();
    _bodyIdsByHandle[nextHandle] = id;
  }

  void setLinearVelocity(String id, Vector3 velocity) {
    _ensureAvailable();
    if (!_isFiniteVector(velocity)) {
      throw ArgumentError.value(velocity, 'velocity');
    }
    final record = _bodies[id];
    if (record == null) return;
    final previous = record.handle;
    final replacement = _BodyRecord(
      id: record.id,
      shape: record.shape,
      motionType: record.motionType,
      transform: Matrix4.copy(record.transform),
      friction: record.friction,
      restitution: record.restitution,
      gravityFactor: record.gravityFactor,
      mass: record.mass,
      layer: record.layer,
      sensor: record.sensor,
      continuous: record.continuous,
      linearDamping: record.linearDamping,
      angularDamping: record.angularDamping,
      linearVelocity: Vector3.copy(velocity),
    );
    final next = _createNativeBody(replacement);
    jolt.jj_body_destroy(previous);
    _bodyIdsByHandle.remove(previous);
    record
      ..handle = next
      ..linearVelocity = Vector3.copy(velocity);
    _bodyIdsByHandle[next] = id;
  }

  String createJoint({
    required String id,
    required String bodyA,
    String? bodyB,
    required PhysicsJointKind kind,
    Vector3 pointA = const Vector3.zero(),
    Vector3 pointB = const Vector3.zero(),
    Vector3 axis = const Vector3(0, 1, 0),
    Vector3 normal = const Vector3(1, 0, 0),
    double? lowerLimit,
    double? upperLimit,
    double maxFriction = 0,
    double motorMaxForce = 0,
    PhysicsJointMotor motor = PhysicsJointMotor.off,
    double motorTarget = 0,
    double springFrequency = 0,
    double springDamping = 0,
  }) {
    _ensureAvailable();
    _validateId(id);
    if (_joints.containsKey(id)) throw StateError('Joint already exists: $id');
    final a = _bodies[bodyA];
    final b = bodyB == null ? null : _bodies[bodyB];
    if (a == null || (bodyB != null && b == null)) {
      throw ArgumentError('Both joint bodies must exist in this world.');
    }
    if (!_isFiniteVector(pointA) ||
        !_isFiniteVector(pointB) ||
        !_isFiniteVector(axis) ||
        !_isFiniteVector(normal) ||
        axis.length2 < 1e-8 ||
        normal.length2 < 1e-8) {
      throw ArgumentError('Joint anchors and axes must be finite and non-zero.');
    }
    if (!maxFriction.isFinite ||
        maxFriction < 0 ||
        !motorMaxForce.isFinite ||
        motorMaxForce < 0 ||
        !motorTarget.isFinite ||
        !springFrequency.isFinite ||
        springFrequency < 0 ||
        !springDamping.isFinite ||
        springDamping < 0) {
      throw ArgumentError('Invalid joint motor or spring settings.');
    }
    final hasLimits = lowerLimit != null || upperLimit != null;
    final minLimit = lowerLimit ?? 0;
    final maxLimit = upperLimit ?? 0;
    if (hasLimits &&
        (!minLimit.isFinite || !maxLimit.isFinite || minLimit > maxLimit)) {
      throw ArgumentError('Joint limits must be finite and ordered.');
    }

    final handle = using((arena) {
      final settings = arena<jolt.JJ_JointSettings>();
      settings.ref
        ..kind = _jointKindValue(kind)
        ..hasLimits = hasLimits
        ..limitMin = minLimit
        ..limitMax = maxLimit
        ..maxFriction = maxFriction
        ..motorMaxForce = motorMaxForce
        ..motorState = _motorValue(motor)
        ..motorTarget = motorTarget
        ..springFrequency = springFrequency
        ..springDamping = springDamping;
      _writeVector(settings.ref.pointA, pointA);
      _writeVector(settings.ref.pointB, pointB);
      _writeVector(settings.ref.axis, axis.normalized());
      _writeVector(settings.ref.normal, normal.normalized());
      return jolt.jj_joint_create(_world, a.handle, b?.handle ?? 0, settings);
    });
    if (handle == 0) throw StateError('Jolt could not create joint $id.');
    _joints[id] = _JointRecord(
      id: id,
      handle: handle,
      bodyA: bodyA,
      bodyB: bodyB,
    );
    return id;
  }

  void setJointEnabled(String id, bool enabled) {
    _ensureAvailable();
    final joint = _joints[id];
    if (joint != null) jolt.jj_joint_set_enabled(joint.handle, enabled);
  }

  void setJointMotor(
    String id, {
    required PhysicsJointMotor motor,
    required double target,
  }) {
    _ensureAvailable();
    if (!target.isFinite) throw ArgumentError.value(target, 'target');
    final joint = _joints[id];
    if (joint != null) {
      jolt.jj_joint_set_motor(joint.handle, _motorValue(motor), target);
    }
  }

  double? jointValue(String id) {
    _ensureAvailable();
    final joint = _joints[id];
    return joint == null ? null : jolt.jj_joint_value(joint.handle);
  }

  void removeJoint(String id) {
    if (_disposed) return;
    final joint = _joints.remove(id);
    if (joint != null) jolt.jj_joint_destroy(joint.handle);
  }

  List<PhysicsContactEvent> drainEvents({int maxEvents = 4096}) {
    _ensureAvailable();
    if (maxEvents < 1) throw ArgumentError.value(maxEvents, 'maxEvents');
    final events = <PhysicsContactEvent>[];
    var remaining = math.min(jolt.jj_pending_events(_world), maxEvents);
    while (remaining > 0) {
      final drained = using((arena) {
        final buffer = arena<jolt.JJ_Event>(remaining);
        final count = jolt.jj_drain_events(_world, buffer, remaining);
        for (var i = 0; i < count; i++) {
          final event = buffer[i];
          events.add(
            PhysicsContactEvent(
              type: event.type,
              bodyA: _bodyIdsByHandle[event.bodyA],
              bodyB: _bodyIdsByHandle[event.bodyB],
              depth: event.depth,
              normal: Vector3(
                event.normal[0],
                event.normal[1],
                event.normal[2],
              ),
              point: Vector3(
                event.point[0],
                event.point[1],
                event.point[2],
              ),
            ),
          );
        }
        return count;
      });
      if (drained == 0 || events.length >= maxEvents) break;
      remaining = math.min(
        jolt.jj_pending_events(_world),
        maxEvents - events.length,
      );
    }
    return events;
  }

  List<PhysicsRaycastHit> raycast(
    Vector3 origin,
    Vector3 direction, {
    int layerMask = 0xFFFF,
    String? ignoreBodyId,
    bool includeSensors = true,
    bool allHits = true,
    int maxHits = 64,
  }) {
    _ensureAvailable();
    if (!_isFiniteVector(origin) ||
        !_isFiniteVector(direction) ||
        direction.length2 < 1e-8 ||
        maxHits < 1 ||
        maxHits > 4096 ||
        layerMask < 0 ||
        layerMask > 0xFFFF) {
      throw ArgumentError('Invalid raycast arguments.');
    }
    final ignored = ignoreBodyId == null
        ? 0
        : (_bodies[ignoreBodyId]?.handle ?? 0);
    return using((arena) {
      final rayOrigin = arena<Float>(3);
      final rayDirection = arena<Float>(3);
      _writeVector(rayOrigin, origin);
      _writeVector(rayDirection, direction);
      final hits = arena<jolt.JJ_Hit>(maxHits);
      var flags = 0;
      if (allHits) flags |= jolt.JJ_QUERY_ALL_HITS;
      if (includeSensors) flags |= jolt.JJ_QUERY_SENSORS;
      final count = jolt.jj_raycast(
        _world,
        rayOrigin,
        rayDirection,
        layerMask,
        ignored,
        flags,
        hits,
        maxHits,
      );
      if (count < 0) throw StateError('Jolt raycast failed: $count');
      return List<PhysicsRaycastHit>.generate(count, (index) {
        final hit = hits[index];
        return PhysicsRaycastHit(
          bodyId: _bodyIdsByHandle[hit.body],
          point: Vector3(hit.point[0], hit.point[1], hit.point[2]),
          normal: Vector3(hit.normal[0], hit.normal[1], hit.normal[2]),
          fraction: hit.fraction,
          depth: hit.depth,
        );
      });
    });
  }

  void removeBody(String id) {
    if (_disposed) return;
    final record = _bodies.remove(id);
    if (record == null) return;
    jolt.jj_body_destroy(record.handle);
    _bodyIdsByHandle.remove(record.handle);
    _joints.removeWhere(
      (_, joint) => joint.bodyA == id || joint.bodyB == id,
    );
  }

  void resetAccumulator() {
    _ensureAvailable();
    _accumulator = 0;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    jolt.jj_world_destroy(_world);
    _bodies.clear();
    _bodyIdsByHandle.clear();
    _joints.clear();
    _accumulator = 0;
  }

  Matrix4 _matrixFromPose(Pointer<Float> values, int offset) {
    final position = Vector3(
      values[offset],
      values[offset + 1],
      values[offset + 2],
    );
    final rotation = Quaternion(
      values[offset + 3],
      values[offset + 4],
      values[offset + 5],
      values[offset + 6],
    );
    return Matrix4.compose(position, rotation, Vector3.all(1));
  }

  ({List<double> position, List<double> rotation}) _toPose(Matrix4 matrix) {
    if (!_isFiniteMatrix(matrix)) {
      throw ArgumentError('Physics transforms must contain only finite values.');
    }
    final position = matrix.getTranslation();
    final rotation = matrix.getRotation();
    final length = math.sqrt(
      rotation.x * rotation.x +
          rotation.y * rotation.y +
          rotation.z * rotation.z +
          rotation.w * rotation.w,
    );
    if (!length.isFinite || length < 1e-8) {
      throw ArgumentError('Physics rotation must be normalizable.');
    }
    return (
      position: <double>[position.x, position.y, position.z],
      rotation: <double>[
        rotation.x / length,
        rotation.y / length,
        rotation.z / length,
        rotation.w / length,
      ],
    );
  }

  void _writeVector(Array<Float> target, Vector3 value) {
    target[0] = value.x;
    target[1] = value.y;
    target[2] = value.z;
  }

  void _writeVector(Pointer<Float> target, Vector3 value) {
    target[0] = value.x;
    target[1] = value.y;
    target[2] = value.z;
  }

  int _jointKindValue(PhysicsJointKind kind) => switch (kind) {
    PhysicsJointKind.fixed => jolt.JJ_JOINT_FIXED,
    PhysicsJointKind.point => jolt.JJ_JOINT_POINT,
    PhysicsJointKind.hinge => jolt.JJ_JOINT_HINGE,
    PhysicsJointKind.slider => jolt.JJ_JOINT_SLIDER,
    PhysicsJointKind.distance => jolt.JJ_JOINT_DISTANCE,
    PhysicsJointKind.sixDof => jolt.JJ_JOINT_SIX_DOF,
  };

  int _motorValue(PhysicsJointMotor motor) => switch (motor) {
    PhysicsJointMotor.off => jolt.JJ_MOTOR_OFF,
    PhysicsJointMotor.velocity => jolt.JJ_MOTOR_VELOCITY,
    PhysicsJointMotor.position => jolt.JJ_MOTOR_POSITION,
  };

  void _validateId(String id) {
    if (id.trim().isEmpty) throw ArgumentError.value(id, 'id');
  }

  void _validatePositive(double value, String name) {
    if (!value.isFinite || value <= 0) throw ArgumentError.value(value, name);
  }

  void _validateMaterial(double friction, double restitution) {
    if (!friction.isFinite ||
        friction < 0 ||
        friction > 1 ||
        !restitution.isFinite ||
        restitution < 0 ||
        restitution > 1) {
      throw ArgumentError('Friction and restitution must be finite in [0, 1].');
    }
  }

  bool _isFiniteVector(Vector3 value) =>
      value.x.isFinite && value.y.isFinite && value.z.isFinite;

  bool _isFiniteMatrix(Matrix4 value) =>
      value.storage.every((component) => component.isFinite);

  void _ensureAvailable() {
    if (_disposed || !jolt.jj_world_valid(_world)) {
      throw StateError('Physics world is not available.');
    }
  }
}
