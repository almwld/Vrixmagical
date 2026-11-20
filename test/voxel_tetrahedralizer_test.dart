import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:virxmagical/services/voxel_tetrahedralizer.dart';

void main() {
  group('VoxelTetrahedralizer', () {
    test('creates six non-degenerate tetrahedra for one occupied voxel', () {
      final result = const VoxelTetrahedralizer().tetrahedralize(
        [Vector3(.5, .5, .5)],
        voxelSizeMeters: 1,
      );

      expect(result.tetrahedronCount, 6);
      expect(result.vertexCount, 8);
      expect(result.boundaryFaceCount, 12);
      expect(result.mesh.triangleCount, 12);
      expect(result.originWorldMeters.x, closeTo(0.5, 1e-9));
      expect(result.originWorldMeters.y, closeTo(0.5, 1e-9));
      expect(result.originWorldMeters.z, closeTo(0.5, 1e-9));
      expect(result.mesh.positions.fold<double>(0, (a, b) => a + b) / result.mesh.positions.length, closeTo(0, 1e-9));
      result.validateQuality();
    });

    test('shares lattice vertices and internal faces across adjacent voxels', () {
      final result = const VoxelTetrahedralizer().tetrahedralize(
        [Vector3(.5, .5, .5), Vector3(1.5, .5, .5)],
        voxelSizeMeters: 1,
      );

      expect(result.tetrahedronCount, 12);
      expect(result.vertexCount, 12);
      expect(result.originWorldMeters.x, closeTo(1.0, 1e-9));
      expect(result.boundaryFaceCount, 20);
      result.validateQuality();
    });

    test('rejects element-budget overflow and empty input', () {
      expect(
        () => const VoxelTetrahedralizer().tetrahedralize(
          [Vector3(.5, .5, .5), Vector3(1.5, .5, .5)],
          voxelSizeMeters: 1,
          maximumTetrahedra: 6,
        ),
        throwsStateError,
      );
      expect(
        () => const VoxelTetrahedralizer().tetrahedralize(
          const <Vector3>[],
          voxelSizeMeters: 1,
        ),
        throwsStateError,
      );
    });
  });
}
