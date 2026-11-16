import 'dart:math' as math;

import 'package:stage_3d/jolt_physics.dart' as jolt;
import 'package:vector_math/vector_math_64.dart';

/// Owns the native 3D rigid-body world used by the AR scene.
///
/// The renderer remains flutter_reality/ARCore; Jolt owns collision detection,
/// rigid-body integration, sleeping, CCD and constraints. Transforms cross this
/// boundary as metres and quaternions (never Euler angles).
class PhysicsSceneService {
  PhysicsSceneService({
    this.fixedStepSeconds = 1 / 60,
    this.maxSubSteps = 5,
  }) : _world = jolt.createPhysicsWorld() {
    if (!fixedStepSeconds.isFinite ||
        fixedStepSeconds <= 0 ||
        maxSubSteps < 1) {
      _world.dispose();
      throw ArgumentError('Physics step and sub-step limits must be positive.');
    }
  }

  final jolt.PhysicsWorld _world;
  final double fixedStepSeconds;
  final int maxSubSteps;
  final Map<String, jolt.RigidBody> _bodies = <String, jolt.RigidBody>{};
  double _accumulator = 0;
  bool _disposed = false;

  String get engineLabel => _world.engineLabel;
  int get bodyCount => _bodies.length;
  bool get isDisposed => _disposed;

  void addStaticBox({
    required String id,
    required Matrix4 worldTransform,
    required Vector3 halfExtents,
    double friction = 0.8,
    double restitution = 0,
  }) {
    _ensureAvailable();
    _validateId(id);
    _validateExtents(halfExtents);
    _validateMaterial(friction, restitution);
    _insertBody(
      id,
      shape: jolt.BoxShape(
        halfWidth: halfExtents.x,
        halfHeight: halfExtents.y,
        halfDepth: halfExtents.z,
      ),
      motionType: jolt.MotionType.static,
      transform: _toPhysicsTransform(worldTransform),
      friction: friction,
      restitution: restitution,
    );
  }

  void addDynamicBox({
    required String id,
    required Matrix4 worldTransform,
    required Vector3 halfExtents,
    Vector3? linearVelocity,
    double friction = 0.55,
    double restitution = 0.08,
  }) {
    _ensureAvailable();
    _validateId(id);
    _validateExtents(halfExtents);
    _validateMaterial(friction, restitution);
    final velocity = linearVelocity ?? Vector3.zero();
    if (!_isFiniteVector(velocity)) {
      throw ArgumentError.value(linearVelocity, 'linearVelocity');
    }
    _insertBody(
      id,
      shape: jolt.BoxShape(
        halfWidth: halfExtents.x,
        halfHeight: halfExtents.y,
        halfDepth: halfExtents.z,
      ),
      motionType: jolt.MotionType.dynamic,
      transform: _toPhysicsTransform(worldTransform),
      linearVelocity: jolt.Vector3(velocity.x, velocity.y, velocity.z),
      friction: friction,
      restitution: restitution,
    );
  }

  void addDynamicSphere({
    required String id,
    required Matrix4 worldTransform,
    required double radius,
    double friction = 0.55,
    double restitution = 0.08,
  }) {
    _ensureAvailable();
    _validateId(id);
    _validateRadius(radius);
    _validateMaterial(friction, restitution);
    _insertBody(
      id,
      shape: jolt.SphereShape(radius: radius),
      motionType: jolt.MotionType.dynamic,
      transform: _toPhysicsTransform(worldTransform),
      friction: friction,
      restitution: restitution,
    );
  }

  void addDynamicCapsule({
    required String id,
    required Matrix4 worldTransform,
    required double radius,
    required double halfHeight,
    double friction = 0.65,
    double restitution = 0.02,
  }) {
    _ensureAvailable();
    _validateId(id);
    _validateRadius(radius);
    if (!halfHeight.isFinite || halfHeight <= 0) {
      throw ArgumentError.value(halfHeight, 'halfHeight');
    }
    _validateMaterial(friction, restitution);
    _insertBody(
      id,
      shape: jolt.CapsuleShape(halfHeight: halfHeight, radius: radius),
      motionType: jolt.MotionType.dynamic,
      transform: _toPhysicsTransform(worldTransform),
      friction: friction,
      restitution: restitution,
    );
  }

  void _insertBody(
    String id, {
    required jolt.ColliderShape shape,
    required jolt.MotionType motionType,
    required jolt.PhysicsTransform transform,
    jolt.Vector3? linearVelocity,
    required double friction,
    required double restitution,
  }) {
    if (_bodies.containsKey(id)) {
      throw StateError('Physics body already exists: $id');
    }
    final body = _world.createBody(
      jolt.RigidBodySettings(
        shape: shape,
        motionType: motionType,
        transform: transform,
        linearVelocity: linearVelocity ?? jolt.Vector3.zero(),
        friction: friction,
        restitution: restitution,
      ),
    );
    _bodies[id] = body;
  }

  /// Advances a bounded fixed-step simulation; large frame stalls cannot cause
  /// an unbounded catch-up loop (the spiral-of-death failure mode).
  int advance(double frameDeltaSeconds) {
    _ensureAvailable();
    if (!frameDeltaSeconds.isFinite || frameDeltaSeconds < 0) {
      throw ArgumentError.value(frameDeltaSeconds, 'frameDeltaSeconds');
    }
    _accumulator += math.min(frameDeltaSeconds, fixedStepSeconds * maxSubSteps);
    var steps = 0;
    while (_accumulator >= fixedStepSeconds && steps < maxSubSteps) {
      _world.step(fixedStepSeconds);
      _accumulator -= fixedStepSeconds;
      steps++;
    }
    if (steps == maxSubSteps && _accumulator >= fixedStepSeconds) {
      _accumulator %= fixedStepSeconds;
    }
    return steps;
  }

  Matrix4 bodyWorldTransform(String id) {
    _ensureAvailable();
    final body = _bodies[id];
    if (body == null) throw StateError('Unknown physics body: $id');
    final transform = _world.getTransform(body);
    final position = Vector3(
      transform.position.x,
      transform.position.y,
      transform.position.z,
    );
    final rotation = Quaternion(
      transform.rotation.x,
      transform.rotation.y,
      transform.rotation.z,
      transform.rotation.w,
    );
    return Matrix4.compose(position, rotation, Vector3.all(1));
  }

  void setBodyWorldTransform(String id, Matrix4 transform) {
    _ensureAvailable();
    final body = _bodies[id];
    if (body == null) return;
    _world.setTransform(body, _toPhysicsTransform(transform));
  }

  void setLinearVelocity(String id, Vector3 velocity) {
    _ensureAvailable();
    if (!_isFiniteVector(velocity)) {
      throw ArgumentError.value(velocity, 'velocity');
    }
    final body = _bodies[id];
    if (body == null) return;
    _world.setLinearVelocity(
      body,
      jolt.Vector3(velocity.x, velocity.y, velocity.z),
    );
  }

  void applyImpulse(String id, Vector3 impulse) {
    _ensureAvailable();
    if (!_isFiniteVector(impulse)) {
      throw ArgumentError.value(impulse, 'impulse');
    }
    final body = _bodies[id];
    if (body == null) return;
    _world.addImpulse(body, jolt.Vector3(impulse.x, impulse.y, impulse.z));
  }

  void removeBody(String id) {
    if (_disposed) return;
    final body = _bodies.remove(id);
    if (body != null) _world.destroyBody(body);
  }

  void resetAccumulator() {
    _ensureAvailable();
    _accumulator = 0;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _bodies.clear();
    _accumulator = 0;
    _world.dispose();
  }

  jolt.PhysicsTransform _toPhysicsTransform(Matrix4 matrix) {
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
      throw ArgumentError('Physics transform rotation must be normalizable.');
    }
    return jolt.PhysicsTransform(
      position: jolt.Vector3(position.x, position.y, position.z),
      rotation: jolt.Quaternion(
        rotation.x / length,
        rotation.y / length,
        rotation.z / length,
        rotation.w / length,
      ),
    );
  }

  void _validateId(String id) {
    if (id.trim().isEmpty) throw ArgumentError.value(id, 'id');
  }

  void _validateExtents(Vector3 extents) {
    if (!_isFiniteVector(extents) ||
        extents.x <= 0 ||
        extents.y <= 0 ||
        extents.z <= 0) {
      throw ArgumentError.value(extents, 'halfExtents');
    }
  }

  void _validateRadius(double radius) {
    if (!radius.isFinite || radius <= 0) {
      throw ArgumentError.value(radius, 'radius');
    }
  }

  void _validateMaterial(double friction, double restitution) {
    if (!friction.isFinite ||
        friction < 0 ||
        friction > 1 ||
        !restitution.isFinite ||
        restitution < 0 ||
        restitution > 1) {
      throw ArgumentError('Friction and restitution must be finite values in [0, 1].');
    }
  }

  bool _isFiniteVector(Vector3 value) =>
      value.x.isFinite && value.y.isFinite && value.z.isFinite;

  bool _isFiniteMatrix(Matrix4 value) =>
      value.storage.every((component) => component.isFinite);

  void _ensureAvailable() {
    if (_disposed) throw StateError('Physics world has already been disposed.');
  }
}
