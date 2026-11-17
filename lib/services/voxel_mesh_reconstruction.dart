import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart';

import 'physics_scene_service.dart';

/// A bounded voxel-surface reconstruction from registered multi-view points.
///
/// This is a conservative, watertight occupancy surface (not a photogrammetry
/// or Poisson reconstruction). It deliberately fails closed when the output
/// would exceed the runtime collider budget.
class ReconstructedVoxelMesh {
  ReconstructedVoxelMesh({
    required this.vertices,
    required this.triangleIndices,
    required this.voxelSizeMeters,
  });

  final List<Vector3> vertices;
  final List<int> triangleIndices;
  final double voxelSizeMeters;

  int get triangleCount => triangleIndices.length ~/ 3;

  void validate() {
    if (!voxelSizeMeters.isFinite || voxelSizeMeters <= 0 ||
        vertices.length < 4 || vertices.length > 100000 ||
        triangleIndices.isEmpty || triangleIndices.length % 3 != 0 ||
        triangleIndices.length > 600000 ||
        vertices.any((v) => !v.x.isFinite || !v.y.isFinite || !v.z.isFinite) ||
        triangleIndices.any((i) => i < 0 || i >= vertices.length)) {
      throw const FormatException('Reconstructed mesh exceeds valid geometry limits.');
    }
  }

  /// Exports a self-contained glTF 2.0 binary (GLB) with POSITION, NORMAL
  /// and indexed TRIANGLES. The file is suitable for standard GLB viewers.
  Future<File> exportGlb(File destination) async {
    validate();
    final positions = ByteData(vertices.length * 3 * 4);
    var offset = 0;
    for (final v in vertices) {
      positions.setFloat32(offset, v.x, Endian.little); offset += 4;
      positions.setFloat32(offset, v.y, Endian.little); offset += 4;
      positions.setFloat32(offset, v.z, Endian.little); offset += 4;
    }
    final normals = _calculateNormals();
    final normalBytes = ByteData(normals.length * 3 * 4);
    offset = 0;
    for (final n in normals) {
      normalBytes.setFloat32(offset, n.x, Endian.little); offset += 4;
      normalBytes.setFloat32(offset, n.y, Endian.little); offset += 4;
      normalBytes.setFloat32(offset, n.z, Endian.little); offset += 4;
    }
    final indexBytes = ByteData(triangleIndices.length * 4);
    for (var i = 0; i < triangleIndices.length; i++) {
      indexBytes.setUint32(i * 4, triangleIndices[i], Endian.little);
    }
    final pos = positions.buffer.asUint8List();
    final nor = normalBytes.buffer.asUint8List();
    final ind = indexBytes.buffer.asUint8List();
    final binaryLength = pos.length + nor.length + ind.length;
    final binary = Uint8List((binaryLength + 3) & ~3);
    binary.setRange(0, pos.length, pos);
    binary.setRange(pos.length, pos.length + nor.length, nor);
    binary.setRange(pos.length + nor.length, binaryLength, ind);

    final min = <double>[double.infinity, double.infinity, double.infinity];
    final max = <double>[double.negativeInfinity, double.negativeInfinity, double.negativeInfinity];
    for (final v in vertices) {
      final values = [v.x, v.y, v.z];
      for (var axis = 0; axis < 3; axis++) {
        min[axis] = math.min(min[axis], values[axis]);
        max[axis] = math.max(max[axis], values[axis]);
      }
    }
    final gltf = <String, Object>{
      'asset': {'version': '2.0', 'generator': 'VRIX voxel surface reconstruction'},
      'scene': 0,
      'scenes': [{'nodes': [0]}],
      'nodes': [{'mesh': 0}],
      'meshes': [{'primitives': [{'attributes': {'POSITION': 0, 'NORMAL': 1}, 'indices': 2, 'mode': 4}]}],
      'buffers': [{'byteLength': binaryLength}],
      'bufferViews': [
        {'buffer': 0, 'byteOffset': 0, 'byteLength': pos.length, 'target': 34962},
        {'buffer': 0, 'byteOffset': pos.length, 'byteLength': nor.length, 'target': 34962},
        {'buffer': 0, 'byteOffset': pos.length + nor.length, 'byteLength': ind.length, 'target': 34963},
      ],
      'accessors': [
        {'bufferView': 0, 'componentType': 5126, 'count': vertices.length, 'type': 'VEC3', 'min': min, 'max': max},
        {'bufferView': 1, 'componentType': 5126, 'count': vertices.length, 'type': 'VEC3'},
        {'bufferView': 2, 'componentType': 5125, 'count': triangleIndices.length, 'type': 'SCALAR'},
      ],
    };
    final json = utf8.encode(jsonEncode(gltf));
    final jsonLength = (json.length + 3) & ~3;
    final jsonChunk = Uint8List(jsonLength)..fillRange(0, jsonLength, 0x20)..setRange(0, json.length, json);
    final totalLength = 12 + 8 + jsonChunk.length + 8 + binary.length;
    final glb = BytesBuilder(copy: false);
    final header = ByteData(12)
      ..setUint32(0, 0x46546C67, Endian.little)
      ..setUint32(4, 2, Endian.little)
      ..setUint32(8, totalLength, Endian.little);
    glb.add(header.buffer.asUint8List());
    final jsonHeader = ByteData(8)
      ..setUint32(0, jsonChunk.length, Endian.little)
      ..setUint32(4, 0x4E4F534A, Endian.little);
    glb.add(jsonHeader.buffer.asUint8List());
    glb.add(jsonChunk);
    final binHeader = ByteData(8)
      ..setUint32(0, binary.length, Endian.little)
      ..setUint32(4, 0x004E4942, Endian.little);
    glb.add(binHeader.buffer.asUint8List());
    glb.add(binary);
    await destination.parent.create(recursive: true);
    await destination.writeAsBytes(glb.takeBytes(), flush: true);
    return destination;
  }

  List<Vector3> _calculateNormals() {
    final result = List<Vector3>.filled(vertices.length, Vector3.zero(), growable: false);
    for (var i = 0; i < triangleIndices.length; i += 3) {
      final a = vertices[triangleIndices[i]];
      final b = vertices[triangleIndices[i + 1]];
      final c = vertices[triangleIndices[i + 2]];
      final normal = (b - a).cross(c - a);
      if (normal.length2 > 1e-18) normal.normalize();
      for (var j = 0; j < 3; j++) {
        result[triangleIndices[i + j]] = normal;
      }
    }
    return result;
  }

  /// Registers the reconstructed surface as a static Jolt triangle mesh.
  void bakeStaticCollider(PhysicsSceneService physics, {required String id}) {
    validate();
    physics.addStaticMesh(
      id: id,
      worldTransform: Matrix4.identity(),
      vertices: vertices,
      triangleIndices: triangleIndices,
    );
  }
}

class VoxelMeshReconstructor {
  const VoxelMeshReconstructor();

  /// Builds the boundary of occupied voxels. Input points must already be
  /// registered in one world coordinate system and filtered by RGB masks,
  /// depth confidence and range before calling this method.
  ReconstructedVoxelMesh reconstruct(
    Iterable<Vector3> points, {
    double voxelSizeMeters = 0.01,
    int maximumOccupiedVoxels = 10000,
    int maximumSurfaceFaces = 25000,
  }) {
    if (!voxelSizeMeters.isFinite || voxelSizeMeters <= 0 ||
        maximumOccupiedVoxels < 8 || maximumSurfaceFaces < 12) {
      throw ArgumentError('Voxel reconstruction limits are invalid.');
    }
    final occupied = <(int, int, int)>{};
    for (final p in points) {
      if (!p.x.isFinite || !p.y.isFinite || !p.z.isFinite) continue;
      occupied.add((
        (p.x / voxelSizeMeters).floor(),
        (p.y / voxelSizeMeters).floor(),
        (p.z / voxelSizeMeters).floor(),
      ));
      if (occupied.length > maximumOccupiedVoxels) {
        throw StateError('Scan exceeds voxel budget; increase voxel size or reduce capture density.');
      }
    }
    if (occupied.length < 8) {
      throw StateError('At least eight occupied voxels are required for a 3D surface.');
    }

    const faces = <({int dx, int dy, int dz, List<List<int>> corners})>[
      (dx: 1, dy: 0, dz: 0, corners: [[1,0,0],[1,1,0],[1,1,1],[1,0,1]]),
      (dx: -1, dy: 0, dz: 0, corners: [[0,0,0],[0,0,1],[0,1,1],[0,1,0]]),
      (dx: 0, dy: 1, dz: 0, corners: [[0,1,0],[0,1,1],[1,1,1],[1,1,0]]),
      (dx: 0, dy: -1, dz: 0, corners: [[0,0,0],[1,0,0],[1,0,1],[0,0,1]]),
      (dx: 0, dy: 0, dz: 1, corners: [[0,0,1],[1,0,1],[1,1,1],[0,1,1]]),
      (dx: 0, dy: 0, dz: -1, corners: [[0,0,0],[0,1,0],[1,1,0],[1,0,0]]),
    ];
    final vertices = <Vector3>[];
    final indices = <int>[];
    for (final cell in occupied) {
      for (final face in faces) {
        if (occupied.contains((cell.$1 + face.dx, cell.$2 + face.dy, cell.$3 + face.dz))) continue;
        if (indices.length ~/ 6 >= maximumSurfaceFaces) {
          throw StateError('Reconstructed surface exceeds Jolt collider triangle budget.');
        }
        final base = vertices.length;
        for (final c in face.corners) {
          vertices.add(Vector3(
            (cell.$1 + c[0]) * voxelSizeMeters,
            (cell.$2 + c[1]) * voxelSizeMeters,
            (cell.$3 + c[2]) * voxelSizeMeters,
          ));
        }
        indices.addAll([base, base + 1, base + 2, base, base + 2, base + 3]);
      }
    }
    final mesh = ReconstructedVoxelMesh(
      vertices: vertices,
      triangleIndices: indices,
      voxelSizeMeters: voxelSizeMeters,
    )..validate();
    return mesh;
  }
}
