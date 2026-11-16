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
  const Collider({required this.objectId, required this.halfExtents, this.mass = 1});
  final String objectId;
  final Vec3 halfExtents;
  final double mass;
}

/// Deterministic fixed-step rigid-body starter for scene interactions. This is
/// deliberately a lightweight domain simulation, not a replacement for a
/// native collision solver; collision response is supplied by the host engine.
class PhysicsBody {
  PhysicsBody({required this.objectId, required this.position, this.velocity = const Vec3.zero(), this.mass = 1});
  final String objectId;
  Vec3 position;
  Vec3 velocity;
  final double mass;
}

class FixedStepPhysics {
  FixedStepPhysics({this.stepSeconds = 1 / 60, this.gravity = const Vec3(0, -9.81, 0), this.maxSubSteps = 5});
  final double stepSeconds;
  final Vec3 gravity;
  final int maxSubSteps;
  final Map<String, PhysicsBody> _bodies = {};
  double _accumulator = 0;
  Iterable<PhysicsBody> get bodies => _bodies.values;

  void addBody(PhysicsBody body) {
    if (body.objectId.isEmpty || !body.mass.isFinite || body.mass <= 0) {
      throw ArgumentError('A physics body needs a stable id and positive finite mass.');
    }
    _bodies[body.objectId] = body;
  }

  void removeBody(String objectId) => _bodies.remove(objectId);

  int advance(double deltaSeconds) {
    if (!deltaSeconds.isFinite || deltaSeconds < 0) throw ArgumentError.value(deltaSeconds, 'deltaSeconds');
    _accumulator += math.min(deltaSeconds, stepSeconds * maxSubSteps).toDouble();
    var steps = 0;
    while (_accumulator >= stepSeconds && steps < maxSubSteps) {
      for (final body in _bodies.values) {
        body.velocity = body.velocity + gravity * stepSeconds;
        body.position = body.position + body.velocity * stepSeconds;
      }
      _accumulator -= stepSeconds;
      steps++;
    }
    return steps;
  }

  void applyImpulse(String objectId, Vec3 impulse) {
    final body = _bodies[objectId];
    if (body == null) return;
    body.velocity = body.velocity + impulse * (1 / body.mass);
  }

  void reset() {
    _bodies.clear();
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
