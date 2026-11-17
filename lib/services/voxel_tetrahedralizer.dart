import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';
import 'package:vrix_soft_body/src/soft_body_contract.dart';

/// Conforming structured-grid tetrahedralization for voxel occupancy.
///
/// Each occupied voxel is split into six Freudenthal tetrahedra along the
/// globally consistent 000->111 diagonal. Shared lattice vertices and
/// boundary faces are deduplicated. This is a volumetric XPBD input mesh,
/// not a constrained-Delaunay tetrahedralization of arbitrary scan geometry.
class TetrahedralizedScan {
  const TetrahedralizedScan({
    required this.mesh,
    required this.minimumAbsoluteSixVolume,
    required this.maximumAbsoluteSixVolume,
    required this.boundaryFaceCount,
  });

  final SoftBodyMeshData mesh;
  final double minimumAbsoluteSixVolume;
  final double maximumAbsoluteSixVolume;
  final int boundaryFaceCount;

  int get tetrahedronCount => mesh.tetrahedronCount;
  int get vertexCount => mesh.vertexCount;

  void validateQuality({double minimumSixVolume = 1e-12}) {
    mesh.validate();
    if (!minimumAbsoluteSixVolume.isFinite ||
        minimumAbsoluteSixVolume < minimumSixVolume ||
        !maximumAbsoluteSixVolume.isFinite ||
        maximumAbsoluteSixVolume < minimumAbsoluteSixVolume ||
        boundaryFaceCount != mesh.triangleCount) {
      throw const FormatException('Tetrahedral mesh failed volume or boundary quality checks.');
    }
  }
}

class VoxelTetrahedralizer {
  const VoxelTetrahedralizer();

  TetrahedralizedScan tetrahedralize(
    Iterable<Vector3> points, {
    required double voxelSizeMeters,
    int maximumOccupiedVoxels = 20000,
    int maximumTetrahedra = 120000,
  }) {
    if (!voxelSizeMeters.isFinite || voxelSizeMeters <= 0 ||
        maximumOccupiedVoxels < 1 || maximumTetrahedra < 6) {
      throw ArgumentError('Tetrahedralization limits must be positive and finite.');
    }

    final occupied = <(int, int, int)>{};
    for (final point in points) {
      if (!point.x.isFinite || !point.y.isFinite || !point.z.isFinite) continue;
      occupied.add((
        (point.x / voxelSizeMeters).floor(),
        (point.y / voxelSizeMeters).floor(),
        (point.z / voxelSizeMeters).floor(),
      ));
      if (occupied.length > maximumOccupiedVoxels) {
        throw StateError('Tetrahedralization exceeds occupied voxel budget.');
      }
    }
    if (occupied.isEmpty) throw StateError('No finite occupied voxels were supplied.');
    if (occupied.length * 6 > maximumTetrahedra) {
      throw StateError('Tetrahedralization exceeds the XPBD element budget.');
    }

    final vertices = <double>[];
    final vertexIds = <(int, int, int), int>{};
    int vertex(int x, int y, int z) => vertexIds.putIfAbsent((x, y, z), () {
      final id = vertices.length ~/ 3;
      vertices.addAll([
        x * voxelSizeMeters,
        y * voxelSizeMeters,
        z * voxelSizeMeters,
      ]);
      return id;
    });

    final tetrahedra = <int>[];
    const offsets = <List<(int, int, int)>>[
      [(0,0,0),(1,0,0),(1,1,0),(1,1,1)],
      [(0,0,0),(1,0,0),(1,0,1),(1,1,1)],
      [(0,0,0),(0,1,0),(1,1,0),(1,1,1)],
      [(0,0,0),(0,1,0),(0,1,1),(1,1,1)],
      [(0,0,0),(0,0,1),(1,0,1),(1,1,1)],
      [(0,0,0),(0,0,1),(0,1,1),(1,1,1)],
    ];

    var minSixVolume = double.infinity;
    var maxSixVolume = 0.0;
    for (final cell in occupied) {
      for (final tet in offsets) {
        final ids = tet.map((p) => vertex(cell.$1 + p.$1, cell.$2 + p.$2, cell.$3 + p.$3)).toList();
        final volume = _sixVolume(vertices, ids[0], ids[1], ids[2], ids[3]);
        if (!volume.isFinite || volume.abs() <= 1e-12) {
          throw StateError('Degenerate tetrahedron generated from voxel occupancy.');
        }
        minSixVolume = math.min(minSixVolume, volume.abs());
        maxSixVolume = math.max(maxSixVolume, volume.abs());
        tetrahedra.addAll(ids);
      }
    }

    // A face shared by two tetrahedra is internal; a face used once is
    // part of the outer surface and becomes the XPBD render surface.
    final faceUses = <(int, int, int), ({int a, int b, int c, int count})>{};
    void addFace(int a, int b, int c) {
      final sorted = [a, b, c]..sort();
      final key = (sorted[0], sorted[1], sorted[2]);
      final old = faceUses[key];
      faceUses[key] = (a: old?.a ?? a, b: old?.b ?? b, c: old?.c ?? c, count: (old?.count ?? 0) + 1);
    }

    for (var i = 0; i < tetrahedra.length; i += 4) {
      final a = tetrahedra[i], b = tetrahedra[i + 1], c = tetrahedra[i + 2], d = tetrahedra[i + 3];
      addFace(a, b, c);
      addFace(a, d, b);
      addFace(a, c, d);
      addFace(b, d, c);
    }
    final surface = <int>[];
    for (final face in faceUses.values) {
      if (face.count == 1) surface.addAll([face.a, face.b, face.c]);
      if (face.count > 2) {
        throw StateError('Non-manifold tetrahedral face has more than two incident elements.');
      }
    }
    if (surface.isEmpty) throw StateError('Tetrahedralization produced no boundary surface.');

    final mesh = SoftBodyMeshData(
      positions: vertices,
      tetrahedronIndices: tetrahedra,
      surfaceTriangleIndices: surface,
    );
    final result = TetrahedralizedScan(
      mesh: mesh,
      minimumAbsoluteSixVolume: minSixVolume,
      maximumAbsoluteSixVolume: maxSixVolume,
      boundaryFaceCount: surface.length ~/ 3,
    );
    result.validateQuality();
    return result;
  }

  double _sixVolume(List<double> p, int a, int b, int c, int d) {
    final ax = p[a * 3], ay = p[a * 3 + 1], az = p[a * 3 + 2];
    final abx = p[b * 3] - ax, aby = p[b * 3 + 1] - ay, abz = p[b * 3 + 2] - az;
    final acx = p[c * 3] - ax, acy = p[c * 3 + 1] - ay, acz = p[c * 3 + 2] - az;
    final adx = p[d * 3] - ax, ady = p[d * 3 + 1] - ay, adz = p[d * 3 + 2] - az;
    return (aby * acz - abz * acy) * adx +
        (abz * acx - abx * acz) * ady +
        (abx * acy - aby * acx) * adz;
  }
}
