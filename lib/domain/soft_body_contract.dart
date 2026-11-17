import 'dart:math' as math;

/// Solver-independent data contracts for VRIX deformable objects.
///
/// Coordinates are object-local metres. The native solver owns simulation
/// state; Flutter owns authoring, interaction intent and rendering.
enum SoftBodyBackendStatus { unavailable, initializing, ready, disposed }

class SoftBodyMeshData {
  SoftBodyMeshData({
    required List<double> positions,
    required List<int> tetrahedronIndices,
    required List<int> surfaceTriangleIndices,
  })  : positions = List<double>.unmodifiable(positions),
        tetrahedronIndices = List<int>.unmodifiable(tetrahedronIndices),
        surfaceTriangleIndices = List<int>.unmodifiable(surfaceTriangleIndices) {
    validate();
  }

  /// Packed XYZ vertex positions in object-local metres.
  final List<double> positions;

  /// Packed groups of four indices, one tetrahedron per group.
  final List<int> tetrahedronIndices;

  /// Packed groups of three indices describing the render/collision surface.
  final List<int> surfaceTriangleIndices;

  int get vertexCount => positions.length ~/ 3;
  int get tetrahedronCount => tetrahedronIndices.length ~/ 4;
  int get triangleCount => surfaceTriangleIndices.length ~/ 3;

  void validate() {
    if (positions.length < 12 || positions.length % 3 != 0 ||
        positions.any((value) => !value.isFinite)) {
      throw const FormatException('Soft-body positions must contain at least four finite XYZ vertices.');
    }
    if (tetrahedronIndices.isEmpty || tetrahedronIndices.length % 4 != 0) {
      throw const FormatException('Soft-body topology must contain tetrahedra (four indices each).');
    }
    if (surfaceTriangleIndices.isEmpty || surfaceTriangleIndices.length % 3 != 0) {
      throw const FormatException('Soft-body surface must contain triangles (three indices each).');
    }
    final allIndices = <int>[...tetrahedronIndices, ...surfaceTriangleIndices];
    if (allIndices.any((index) => index < 0 || index >= vertexCount)) {
      throw const FormatException('Soft-body topology references a vertex outside the mesh.');
    }
    for (var i = 0; i < tetrahedronIndices.length; i += 4) {
      final a = tetrahedronIndices[i];
      final b = tetrahedronIndices[i + 1];
      final c = tetrahedronIndices[i + 2];
      final d = tetrahedronIndices[i + 3];
      if ({a, b, c, d}.length != 4) {
        throw const FormatException('A tetrahedron cannot repeat a vertex index.');
      }
      final ax = positions[a * 3], ay = positions[a * 3 + 1], az = positions[a * 3 + 2];
      final abx = positions[b * 3] - ax, aby = positions[b * 3 + 1] - ay, abz = positions[b * 3 + 2] - az;
      final acx = positions[c * 3] - ax, acy = positions[c * 3 + 1] - ay, acz = positions[c * 3 + 2] - az;
      final adx = positions[d * 3] - ax, ady = positions[d * 3 + 1] - ay, adz = positions[d * 3 + 2] - az;
      final crossX = aby * acz - abz * acy;
      final crossY = abz * acx - abx * acz;
      final crossZ = abx * acy - aby * acx;
      final sixVolume = crossX * adx + crossY * ady + crossZ * adz;
      if (!sixVolume.isFinite || sixVolume.abs() <= 1e-9) {
        throw const FormatException('Tetrahedra must have non-zero finite rest volume.');
      }
    }
    for (var i = 0; i < surfaceTriangleIndices.length; i += 3) {
      if ({
        surfaceTriangleIndices[i],
        surfaceTriangleIndices[i + 1],
        surfaceTriangleIndices[i + 2],
      }.length != 3) {
        throw const FormatException('A surface triangle cannot repeat a vertex index.');
      }
    }
  }
}

class SoftBodyMaterial {
  const SoftBodyMaterial({
    this.densityKgPerM3 = 1000,
    this.youngsModulusPa = 25000,
    this.poissonRatio = 0.35,
    this.damping = 0.02,
  });

  final double densityKgPerM3;
  final double youngsModulusPa;
  final double poissonRatio;
  final double damping;

  void validate() {
    if (!densityKgPerM3.isFinite || densityKgPerM3 <= 0 ||
        !youngsModulusPa.isFinite || youngsModulusPa <= 0 ||
        !poissonRatio.isFinite || poissonRatio < 0 || poissonRatio > 0.49 ||
        !damping.isFinite || damping < 0) {
      throw const FormatException('Invalid soft-body material parameters.');
    }
  }
}

class SoftBodySolverConfig {
  const SoftBodySolverConfig({
    this.fixedTimeStepSeconds = 1 / 60,
    this.solverIterations = 8,
    this.maxSubSteps = 4,
    this.selfCollision = false,
  });

  final double fixedTimeStepSeconds;
  final int solverIterations;
  final int maxSubSteps;
  final bool selfCollision;

  void validate() {
    if (!fixedTimeStepSeconds.isFinite || fixedTimeStepSeconds <= 0 ||
        solverIterations < 1 || solverIterations > 64 ||
        maxSubSteps < 1 || maxSubSteps > 16) {
      throw const FormatException('Invalid soft-body solver limits.');
    }
  }
}

class SoftBodyHandle {
  const SoftBodyHandle._(this.value);
  final int value;
  static SoftBodyHandle fromNative(int value) {
    if (value <= 0) throw ArgumentError.value(value, 'value');
    return SoftBodyHandle._(value);
  }
}

class SoftBodyState {
  SoftBodyState({required List<double> positions, required List<double> velocities})
      : positions = List<double>.unmodifiable(positions),
        velocities = List<double>.unmodifiable(velocities) {
    if (this.positions.isEmpty || this.positions.length % 3 != 0 ||
        this.velocities.length != this.positions.length ||
        this.positions.any((v) => !v.isFinite) ||
        this.velocities.any((v) => !v.isFinite)) {
      throw const FormatException('Soft-body state must contain matching finite XYZ positions and velocities.');
    }
  }

  final List<double> positions;
  final List<double> velocities;
}

/// Adapter boundary: XPBD owns deformable state; Jolt remains the rigid-body
/// and collision world. Neither Flutter widgets nor ARCore depend on a solver.
abstract interface class VrixSoftBodyEngine {
  SoftBodyBackendStatus get status;

  SoftBodyHandle createBody({
    required SoftBodyMeshData mesh,
    required SoftBodyMaterial material,
    required SoftBodySolverConfig config,
  });

  void step(double deltaSeconds);

  void setPointTarget({
    required SoftBodyHandle body,
    required int vertexIndex,
    required List<double> targetWorldPosition,
    double compliance = 0,
  });

  SoftBodyState readState(SoftBodyHandle body);

  void removeBody(SoftBodyHandle body);

  void dispose();
}
