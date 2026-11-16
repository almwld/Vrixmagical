import 'dart:math' as math;
import 'dart:typed_data';

/// Explicit capability states prevent a research prototype from being shown as
/// a production feature when its native runtime is not installed.
enum RuntimeCapabilityState { available, fallback, unsupported, notProbed }

class RuntimeCapability {
  const RuntimeCapability(this.state, this.reason);
  final RuntimeCapabilityState state;
  final String reason;
}

/// Stable identity and transform contract shared by AR, physics, capture and
/// voice commands. Coordinates are metres in the app's world coordinate space.
class SceneObject {
  const SceneObject({
    required this.id,
    required this.position,
    this.rotation = const Vec3.zero(),
    this.scale = const Vec3.one(),
    this.visible = true,
  });
  final String id;
  final Vec3 position;
  final Vec3 rotation;
  final Vec3 scale;
  final bool visible;

  SceneObject copyWith({
    Vec3? position,
    Vec3? rotation,
    Vec3? scale,
    bool? visible,
  }) => SceneObject(
    id: id,
    position: position ?? this.position,
    rotation: rotation ?? this.rotation,
    scale: scale ?? this.scale,
    visible: visible ?? this.visible,
  );
}

class Vec3 {
  const Vec3(this.x, this.y, this.z);
  const Vec3.zero() : this(0, 0, 0);
  const Vec3.one() : this(1, 1, 1);
  final double x;
  final double y;
  final double z;
  Vec3 operator +(Vec3 other) => Vec3(x + other.x, y + other.y, z + other.z);
  Vec3 operator -(Vec3 other) => Vec3(x - other.x, y - other.y, z - other.z);
  Vec3 operator *(double factor) => Vec3(x * factor, y * factor, z * factor);
  double get length => math.sqrt(x * x + y * y + z * z);
  static Vec3 lerp(Vec3 a, Vec3 b, double t) => a + (b - a) * t;
}

bool _isFiniteVec3(Vec3 value) =>
    value.x.isFinite && value.y.isFinite && value.z.isFinite;

/// Two-hand transform math ported from the hand-interaction research projects.
/// Callers own landmark tracking and coordinate-space conversion.
class TwoHandTransform {
  const TwoHandTransform({required this.midpoint, required this.distance, required this.angle});
  final Vec3 midpoint;
  final double distance;
  final double angle;

  static TwoHandTransform? fromPoints(Vec3 first, Vec3 second) {
    final delta = second - first;
    final distance = delta.length;
    if (!distance.isFinite || distance < 1e-5) return null;
    return TwoHandTransform(
      midpoint: Vec3.lerp(first, second, .5),
      distance: distance,
      angle: math.atan2(delta.y, delta.x),
    );
  }

  Vec3 applyScale(Vec3 initialScale, double initialDistance) {
    if (!initialDistance.isFinite || initialDistance <= 1e-5) return initialScale;
    final factor = (distance / initialDistance).clamp(.1, 10.0).toDouble();
    return initialScale * factor;
  }
}

enum PerformanceTier { high, balanced, low }

/// Simple hysteretic governor. It never changes model quality while a frame is
/// being processed; the host applies the tier at the next safe frame boundary.
class AdaptivePerformanceGovernor {
  PerformanceTier _tier = PerformanceTier.balanced;
  int _slowFrames = 0;
  int _fastFrames = 0;
  PerformanceTier get tier => _tier;

  PerformanceTier recordFrame(Duration elapsed, {Duration budget = const Duration(milliseconds: 33)}) {
    if (elapsed > budget) {
      _slowFrames++;
      _fastFrames = 0;
    } else if (elapsed < budget * .65) {
      _fastFrames++;
      _slowFrames = 0;
    } else {
      _slowFrames = 0;
      _fastFrames = 0;
    }
    if (_slowFrames >= 12) {
      _tier = _tier == PerformanceTier.high ? PerformanceTier.balanced : PerformanceTier.low;
      _slowFrames = 0;
    } else if (_fastFrames >= 90) {
      _tier = _tier == PerformanceTier.low ? PerformanceTier.balanced : PerformanceTier.high;
      _fastFrames = 0;
    }
    return _tier;
  }
}

/// One-in-flight frame gate with timeout recovery. A monotonically increasing
/// generation lets callers discard callbacks from a timed-out native request.
class FrameRequestGate {
  FrameRequestGate({this.timeout = const Duration(seconds: 2)});
  final Duration timeout;
  bool _busy = false;
  int _generation = 0;
  DateTime? _startedAt;
  bool get isBusy => _busy;
  int get generation => _generation;

  int? tryStart(DateTime now) {
    recoverIfStale(now);
    if (_busy) return null;
    _busy = true;
    _startedAt = now;
    return ++_generation;
  }

  bool complete(int requestGeneration) {
    if (!_busy || requestGeneration != _generation) return false;
    _busy = false;
    _startedAt = null;
    return true;
  }

  bool recoverIfStale(DateTime now) {
    final started = _startedAt;
    if (!_busy || started == null || now.difference(started) <= timeout) return false;
    _busy = false;
    _startedAt = null;
    _generation++;
    return true;
  }

  void reset() {
    _busy = false;
    _startedAt = null;
    _generation++;
  }
}

class Collider {
  const Collider({
    required this.objectId,
    required this.halfExtents,
    this.mass = 1,
    this.isStatic = false,
    this.restitution = .05,
    this.friction = .5,
  });

  final String objectId;
  /// Axis-aligned half extents in world metres. Rotation is not represented.
  final Vec3 halfExtents;
  final double mass;
  final bool isStatic;
  final double restitution;
  final double friction;
}

/// Rigid body state in the shared scene coordinate system.
class PhysicsBody {
  PhysicsBody({
    required this.objectId,
    required this.position,
    this.velocity = const Vec3.zero(),
    this.mass = 1,
  });

  final String objectId;
  Vec3 position;
  Vec3 velocity;
  final double mass;
}

/// Fixed-step AABB collision world. This is a deterministic lightweight solver
/// for simple digital props; it is not a substitute for a full 3D engine.
class FixedStepPhysics {
  FixedStepPhysics({
    this.stepSeconds = 1 / 60,
    this.gravity = const Vec3(0, -9.81, 0),
    this.maxSubSteps = 5,
    this.solverIterations = 4,
  });

  final double stepSeconds;
  final Vec3 gravity;
  final int maxSubSteps;
  final int solverIterations;
  final Map<String, PhysicsBody> _bodies = {};
  final Map<String, Collider> _colliders = {};
  double _accumulator = 0;

  Iterable<PhysicsBody> get bodies => List.unmodifiable(_bodies.values);
  Iterable<Collider> get colliders => List.unmodifiable(_colliders.values);

  void addBody(PhysicsBody body) {
    if (body.objectId.trim().isEmpty ||
        !_isFiniteVec3(body.position) ||
        !_isFiniteVec3(body.velocity) ||
        !body.mass.isFinite || body.mass <= 0) {
      throw ArgumentError('A physics body needs a stable id, finite transforms and positive finite mass.');
    }
    _bodies[body.objectId] = body;
  }

  void addCollider(Collider collider) {
    final extents = collider.halfExtents;
    if (!_bodies.containsKey(collider.objectId)) {
      throw StateError('A collider must reference an existing physics body.');
    }
    if (collider.objectId.isEmpty ||
        !extents.x.isFinite || !extents.y.isFinite || !extents.z.isFinite ||
        extents.x <= 0 || extents.y <= 0 || extents.z <= 0 ||
        !collider.restitution.isFinite || collider.restitution < 0 || collider.restitution > 1 ||
        !collider.friction.isFinite || collider.friction < 0 || collider.friction > 1) {
      throw ArgumentError('Collider dimensions and material coefficients must be finite and within their physical ranges.');
    }
    _colliders[collider.objectId] = collider;
  }

  void removeCollider(String objectId) => _colliders.remove(objectId);

  void removeBody(String objectId) {
    _bodies.remove(objectId);
    _colliders.remove(objectId);
  }

  int advance(double deltaSeconds) {
    if (!deltaSeconds.isFinite || deltaSeconds < 0) {
      throw ArgumentError.value(deltaSeconds, 'deltaSeconds');
    }
    if (!stepSeconds.isFinite || stepSeconds <= 0 || maxSubSteps < 1 || solverIterations < 1) {
      throw StateError('Physics step and iteration limits must be positive.');
    }
    _accumulator += math.min(deltaSeconds, stepSeconds * maxSubSteps).toDouble();
    var steps = 0;
    while (_accumulator >= stepSeconds && steps < maxSubSteps) {
      _simulateStep();
      _accumulator -= stepSeconds;
      steps++;
    }
    return steps;
  }

  void _simulateStep() {
    for (final body in _bodies.values) {
      if (_colliders[body.objectId]?.isStatic ?? false) continue;
      body.velocity = body.velocity + gravity * stepSeconds;
      body.position = body.position + body.velocity * stepSeconds;
    }
    for (var iteration = 0; iteration < solverIterations; iteration++) {
      _resolveAabbContacts();
    }
  }

  void _resolveAabbContacts() {
    final active = _colliders.values
        .where((collider) => _bodies.containsKey(collider.objectId))
        .toList(growable: false);
    for (var i = 0; i < active.length; i++) {
      for (var j = i + 1; j < active.length; j++) {
        final a = active[i];
        final b = active[j];
        if (a.isStatic && b.isStatic) continue;
        final bodyA = _bodies[a.objectId]!;
        final bodyB = _bodies[b.objectId]!;
        final delta = bodyB.position - bodyA.position;
        final overlapX = a.halfExtents.x + b.halfExtents.x - delta.x.abs();
        final overlapY = a.halfExtents.y + b.halfExtents.y - delta.y.abs();
        final overlapZ = a.halfExtents.z + b.halfExtents.z - delta.z.abs();
        if (overlapX <= 0 || overlapY <= 0 || overlapZ <= 0) continue;

        final penetration = math.min(overlapX, math.min(overlapY, overlapZ)).toDouble();
        final normal = overlapX <= overlapY && overlapX <= overlapZ
            ? Vec3(delta.x >= 0 ? 1 : -1, 0, 0)
            : overlapY <= overlapZ
                ? Vec3(0, delta.y >= 0 ? 1 : -1, 0)
                : Vec3(0, 0, delta.z >= 0 ? 1 : -1);
        final inverseMassA = a.isStatic ? 0.0 : 1 / bodyA.mass;
        final inverseMassB = b.isStatic ? 0.0 : 1 / bodyB.mass;
        final inverseMassSum = inverseMassA + inverseMassB;
        if (inverseMassSum <= 0) continue;

        // Positional correction prevents persistent interpenetration without
        // injecting a large velocity into resting objects.
        final correctionMagnitude = math.max(0.0, penetration - .0005) * .8 / inverseMassSum;
        if (!a.isStatic) {
          bodyA.position = bodyA.position - normal * (correctionMagnitude * inverseMassA);
        }
        if (!b.isStatic) {
          bodyB.position = bodyB.position + normal * (correctionMagnitude * inverseMassB);
        }

        final relativeVelocity = bodyB.velocity - bodyA.velocity;
        final velocityAlongNormal = _dot(relativeVelocity, normal);
        if (velocityAlongNormal > 0) continue;
        final restitution = math.min(a.restitution, b.restitution).toDouble();
        final impulseMagnitude = -(1 + restitution) * velocityAlongNormal / inverseMassSum;
        final impulse = normal * impulseMagnitude;
        if (!a.isStatic) {
          bodyA.velocity = bodyA.velocity - impulse * inverseMassA;
        }
        if (!b.isStatic) {
          bodyB.velocity = bodyB.velocity + impulse * inverseMassB;
        }

        // Coulomb-style friction impulse, bounded by the normal impulse.
        final postImpulseRelative = bodyB.velocity - bodyA.velocity;
        final tangentVelocity = postImpulseRelative - normal * _dot(postImpulseRelative, normal);
        final tangentLength = tangentVelocity.length;
        if (tangentLength <= 1e-8 || impulseMagnitude <= 0) continue;
        final tangent = tangentVelocity * (1 / tangentLength);
        var frictionImpulseMagnitude = -_dot(postImpulseRelative, tangent) / inverseMassSum;
        final frictionLimit = impulseMagnitude * math.sqrt(a.friction * b.friction);
        frictionImpulseMagnitude = frictionImpulseMagnitude
            .clamp(-frictionLimit, frictionLimit)
            .toDouble();
        final frictionImpulse = tangent * frictionImpulseMagnitude;
        if (!a.isStatic) {
          bodyA.velocity = bodyA.velocity - frictionImpulse * inverseMassA;
        }
        if (!b.isStatic) {
          bodyB.velocity = bodyB.velocity + frictionImpulse * inverseMassB;
        }
      }
    }
  }

  double _dot(Vec3 a, Vec3 b) => a.x * b.x + a.y * b.y + a.z * b.z;

  void applyImpulse(String objectId, Vec3 impulse) {
    if (!_isFiniteVec3(impulse)) {
      throw ArgumentError.value(impulse, 'impulse', 'Impulse components must be finite.');
    }
    final body = _bodies[objectId];
    if (body == null || (_colliders[objectId]?.isStatic ?? false)) return;
    body.velocity = body.velocity + impulse * (1 / body.mass);
  }

  void reset() {
    _bodies.clear();
    _colliders.clear();
    _accumulator = 0;
  }
}

class CaptureFrame {
  const CaptureFrame({required this.path, required this.timestampMicros, required this.cameraPose, this.depthPath});
  final String path;
  final int timestampMicros;
  final List<double> cameraPose;
  final String? depthPath;
}

class CaptureManifest {
  CaptureManifest({required this.sessionId});
  final String sessionId;
  final List<CaptureFrame> _frames = [];
  List<CaptureFrame> get frames => List.unmodifiable(_frames);

  void add(CaptureFrame frame) {
    if (frame.path.isEmpty || frame.timestampMicros < 0 || frame.cameraPose.length != 16 ||
        frame.cameraPose.any((value) => !value.isFinite)) {
      throw ArgumentError('Capture frame requires a path, non-negative timestamp and finite 4x4 camera pose.');
    }
    if (_frames.isNotEmpty && frame.timestampMicros <= _frames.last.timestampMicros) {
      throw StateError('Capture timestamps must be strictly increasing.');
    }
    _frames.add(frame);
  }
}

enum SceneCommandType { select, move, hide, show, duplicate, delete }

class SceneCommand {
  const SceneCommand({required this.type, required this.objectId, this.position, this.requiresConfirmation = false});
  final SceneCommandType type;
  final String objectId;
  final Vec3? position;
  final bool requiresConfirmation;
}

/// Voice/NL input must be converted into this allow-listed schema before it can
/// touch the scene. Unknown phrases are rejected rather than executed.
class SceneCommandParser {
  static SceneCommand? parse(String input, Set<String> knownObjectIds) {
    final text = input.trim().toLowerCase();
    final match = RegExp(r'^(hide|show|delete|duplicate|select)\s+([a-z0-9_-]+)$').firstMatch(text);
    if (match == null) return null;
    final id = match.group(2)!;
    if (!knownObjectIds.contains(id)) return null;
    final action = match.group(1)!;
    final type = switch (action) {
      'hide' => SceneCommandType.hide,
      'show' => SceneCommandType.show,
      'delete' => SceneCommandType.delete,
      'duplicate' => SceneCommandType.duplicate,
      _ => SceneCommandType.select,
    };
    return SceneCommand(
      type: type,
      objectId: id,
      requiresConfirmation: type == SceneCommandType.delete || type == SceneCommandType.duplicate,
    );
  }
}


/// In-memory scene identity owner. Persistence is intentionally delegated to
/// the app's storage layer; IDs remain stable across renderer/physics adapters.
class SceneObjectRegistry {
  final Map<String, SceneObject> _objects = {};
  Iterable<SceneObject> get objects => List.unmodifiable(_objects.values);
  SceneObject? operator [](String id) => _objects[id];

  void register(SceneObject object) {
    if (object.id.trim().isEmpty) throw ArgumentError('Scene object id cannot be empty.');
    if (_objects.containsKey(object.id)) throw StateError('Scene object already exists: ${object.id}');
    _objects[object.id] = object;
  }

  bool apply(SceneCommand command, {bool confirmed = false}) {
    final object = _objects[command.objectId];
    if (object == null) return false;
    if (command.requiresConfirmation && !confirmed) return false;
    switch (command.type) {
      case SceneCommandType.select:
        return true;
      case SceneCommandType.move:
        if (command.position == null) return false;
        _objects[object.id] = object.copyWith(position: command.position);
        return true;
      case SceneCommandType.hide:
        _objects[object.id] = object.copyWith(visible: false);
        return true;
      case SceneCommandType.show:
        _objects[object.id] = object.copyWith(visible: true);
        return true;
      case SceneCommandType.duplicate:
        final duplicateId = '${object.id}_copy';
        if (_objects.containsKey(duplicateId)) return false;
        _objects[duplicateId] = SceneObject(
          id: duplicateId,
          position: object.position,
          rotation: object.rotation,
          scale: object.scale,
          visible: object.visible,
        );
        return true;
      case SceneCommandType.delete:
        _objects.remove(object.id);
        return true;
    }
  }

  void clear() => _objects.clear();
}

/// Safe segmentation contract: an EdgeSAM implementation can be injected only
/// after the native ONNX runtime and verified model artifacts are present.
abstract interface class PromptSegmentationBackend {
  RuntimeCapability get capability;
  Future<Uint8List> segment({
    required String imagePath,
    required List<SegmentationPrompt> prompts,
  });
}

class SegmentationPrompt {
  const SegmentationPrompt({required this.x, required this.y, required this.positive});
  final double x;
  final double y;
  final bool positive;
}

class FallbackSegmentationBackend implements PromptSegmentationBackend {
  const FallbackSegmentationBackend();
  @override
  RuntimeCapability get capability => const RuntimeCapability(
    RuntimeCapabilityState.fallback,
    'MediaPipe Interactive Segmenter remains the active app fallback; EdgeSAM ONNX runtime is not bundled.',
  );
  @override
  Future<Uint8List> segment({required String imagePath, required List<SegmentationPrompt> prompts}) =>
      Future.error(UnsupportedError('Use the existing MediaPipe Interactive Segmenter UI adapter.'));
}

/// Device-specific native probes remain explicitly unverified until the host
/// platform channel returns actual ARCore/Vulkan capabilities.
class ResearchRuntimeCapabilities {
  const ResearchRuntimeCapabilities({
    this.edgeSam = const RuntimeCapability(RuntimeCapabilityState.fallback, 'MediaPipe fallback; EdgeSAM model/runtime not bundled.'),
    this.depth = const RuntimeCapability(RuntimeCapabilityState.notProbed, 'ARCore depth bridge is not installed in the generated Android host.'),
    this.physics = const RuntimeCapability(RuntimeCapabilityState.fallback, 'Fixed-step scene motion is available; native collision solving is not integrated.'),
    this.reconstruction = const RuntimeCapability(RuntimeCapabilityState.unsupported, 'Capture metadata is available; mobile SLAM/point-cloud/splat reconstruction is not implemented.'),
    this.splatAdvanced = const RuntimeCapability(RuntimeCapabilityState.notProbed, 'Pinned SplatKit beta.3 viewer is present; advanced tileset/collider APIs have not been runtime-probed.'),
    this.voice = const RuntimeCapability(RuntimeCapabilityState.unsupported, 'Typed scene command schema is available; speech recognition is not integrated.'),
  });
  final RuntimeCapability edgeSam;
  final RuntimeCapability depth;
  final RuntimeCapability physics;
  final RuntimeCapability reconstruction;
  final RuntimeCapability splatAdvanced;
  final RuntimeCapability voice;
}
