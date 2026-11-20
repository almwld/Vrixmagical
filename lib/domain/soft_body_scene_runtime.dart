import 'package:vector_math/vector_math_64.dart';
import 'package:vrix_soft_body/vrix_soft_body.dart';

import '../services/coupled_soft_body_physics.dart';
import '../services/object_scan_reconstruction_service.dart';
import '../services/physics_scene_service.dart';

/// Immutable, renderer-neutral snapshot of a deformable object's surface.
///
/// Positions remain object-local metres. A renderer applies [worldTransform]
/// and indexes the packed XYZ positions with [surfaceTriangleIndices].
class SoftBodyRenderFrame {
  SoftBodyRenderFrame({
    required this.frameNumber,
    required List<double> positions,
    required List<double> velocities,
    required List<int> surfaceTriangleIndices,
    required Matrix4 worldTransform,
  })  : positions = List<double>.unmodifiable(positions),
        velocities = List<double>.unmodifiable(velocities),
        surfaceTriangleIndices =
            List<int>.unmodifiable(surfaceTriangleIndices),
        worldTransform = Matrix4.copy(worldTransform) {
    if (frameNumber < 0 ||
        positions.isEmpty ||
        positions.length % 3 != 0 ||
        velocities.length != positions.length ||
        positions.any((value) => !value.isFinite) ||
        velocities.any((value) => !value.isFinite) ||
        surfaceTriangleIndices.isEmpty ||
        surfaceTriangleIndices.length % 3 != 0 ||
        surfaceTriangleIndices.any(
          (index) => index < 0 || index >= positions.length ~/ 3,
        ) ||
        worldTransform.storage.any((value) => !value.isFinite)) {
      throw const FormatException('Invalid deformable render-frame buffers.');
    }
  }

  final int frameNumber;
  final List<double> positions;
  final List<double> velocities;
  final List<int> surfaceTriangleIndices;
  final Matrix4 worldTransform;

  int get vertexCount => positions.length ~/ 3;
  int get triangleCount => surfaceTriangleIndices.length ~/ 3;
}

/// Owns the scan -> native XPBD/FEM -> Jolt coupling lifecycle for one object.
///
/// The rigid [scene] is borrowed and remains owned by its caller. Dispose this
/// runtime before disposing that scene. The returned surface snapshots are the
/// renderer boundary; a GPU/AR mesh uploader can consume them without owning or
/// stepping either physics engine.
class VrixSoftBodySceneRuntime {
  VrixSoftBodySceneRuntime._({
    required this.engine,
    required this.scene,
    required this.mesh,
    required this.softBody,
    required this.coupling,
    required this.worldTransform,
  });

  final VrixSoftBodyFfiEngine engine;
  final PhysicsSceneService scene;
  final SoftBodyMeshData mesh;
  final SoftBodyHandle softBody;
  final CoupledSoftBodyPhysics coupling;
  final Matrix4 worldTransform;

  bool _disposed = false;
  int _frameNumber = 0;

  bool get isDisposed => _disposed;
  int get coupledSteps => coupling.coupledSteps;
  int get activeContactCount => coupling.activeContactCount;
  int get lastAppliedReactionCount => coupling.lastAppliedReactionCount;
  Vector3 get lastAppliedReactionImpulse =>
      coupling.lastAppliedReactionImpulse;

  /// Creates the native deformable body from a completed scan's tetrahedral
  /// volume and registers its kinematic collision proxy in the existing Jolt
  /// world. The caller supplies the AR/world transform used for placement.
  factory VrixSoftBodySceneRuntime.fromReconstruction({
    required ObjectScanReconstructionResult reconstruction,
    required PhysicsSceneService scene,
    required String objectId,
    required Matrix4 worldTransform,
    SoftBodyMaterial material = const SoftBodyMaterial(),
    SoftBodySolverConfig config = const SoftBodySolverConfig(),
    double contactFriction = 0.5,
    double contactCompliance = 0,
    double maxContactDistance = 0.08,
  }) {
    if (objectId.trim().isEmpty) {
      throw ArgumentError.value(objectId, 'objectId');
    }
    final mesh = reconstruction.tetrahedralization.mesh;
    mesh.validate();
    final engine = VrixSoftBodyFfiEngine.open();
    SoftBodyHandle? body;
    try {
      body = engine.createBody(
        mesh: mesh,
        material: material,
        config: config,
      );
      final coupling = CoupledSoftBodyPhysics(
        scene: scene,
        engine: engine,
        softBody: body,
        mesh: mesh,
        proxyBodyId: 'soft:$objectId',
        initialTransform: worldTransform,
        contactFriction: contactFriction,
        contactCompliance: contactCompliance,
        maxContactDistance: maxContactDistance,
      );
      return VrixSoftBodySceneRuntime._(
        engine: engine,
        scene: scene,
        mesh: mesh,
        softBody: body,
        coupling: coupling,
        worldTransform: Matrix4.copy(worldTransform),
      );
    } catch (_) {
      if (body != null) engine.removeBody(body);
      engine.dispose();
      rethrow;
    }
  }

  /// Advances both engines through the coupled fixed-step adapter and returns
  /// the current deforming surface for the renderer.
  SoftBodyRenderFrame advance(double deltaSeconds) {
    _ensureActive();
    coupling.advance(deltaSeconds);
    _frameNumber++;
    return readFrame();
  }

  /// Reads the current XPBD state without advancing simulation.
  SoftBodyRenderFrame readFrame() {
    _ensureActive();
    final state = engine.readState(softBody);
    if (state.positions.length != mesh.vertexCount * 3) {
      throw StateError('Native XPBD state no longer matches its source mesh.');
    }
    return SoftBodyRenderFrame(
      frameNumber: _frameNumber,
      positions: state.positions,
      velocities: state.velocities,
      surfaceTriangleIndices: mesh.surfaceTriangleIndices,
      worldTransform: worldTransform,
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    try {
      coupling.dispose();
    } finally {
      engine.removeBody(softBody);
      engine.dispose();
    }
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('The VRIX soft-body scene runtime has been disposed.');
    }
  }
}
