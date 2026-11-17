import 'package:flutter_test/flutter_test.dart';
import 'package:virxmagical/domain/soft_body_contract.dart';

void main() {
  group('SoftBodyMeshData', () {
    const positions = <double>[
      0, 0, 0,
      1, 0, 0,
      0, 1, 0,
      0, 0, 1,
    ];
    const tetrahedra = <int>[0, 1, 2, 3];
    const surface = <int>[0, 2, 1, 0, 1, 3, 1, 2, 3, 2, 0, 3];

    test('accepts a valid tetrahedral volume and immutable surface mapping', () {
      final mesh = SoftBodyMeshData(
        positions: positions,
        tetrahedronIndices: tetrahedra,
        surfaceTriangleIndices: surface,
      );
      expect(mesh.vertexCount, 4);
      expect(mesh.tetrahedronCount, 1);
      expect(mesh.triangleCount, 4);
    });

    test('rejects out-of-range topology', () {
      expect(
        () => SoftBodyMeshData(
          positions: positions,
          tetrahedronIndices: const [0, 1, 2, 4],
          surfaceTriangleIndices: surface,
        ),
        throwsFormatException,
      );
    });

    test('rejects degenerate tetrahedra', () {
      expect(
        () => SoftBodyMeshData(
          positions: const [
            0, 0, 0,
            1, 0, 0,
            0, 1, 0,
            1, 1, 0,
          ],
          tetrahedronIndices: tetrahedra,
          surfaceTriangleIndices: surface,
        ),
        throwsFormatException,
      );
    });

    test('rejects repeated tetrahedron vertices', () {
      expect(
        () => SoftBodyMeshData(
          positions: positions,
          tetrahedronIndices: const [0, 1, 1, 3],
          surfaceTriangleIndices: surface,
        ),
        throwsFormatException,
      );
    });
  });

  test('validates SI material and bounded solver settings', () {
    const material = SoftBodyMaterial();
    const config = SoftBodySolverConfig();
    expect(material.validate, returnsNormally);
    expect(config.validate, returnsNormally);
    expect(
      () => const SoftBodyMaterial(poissonRatio: 0.5).validate(),
      throwsFormatException,
    );
    expect(
      () => const SoftBodySolverConfig(solverIterations: 0).validate(),
      throwsFormatException,
    );
  });

  test('state buffers must be matching finite XYZ arrays', () {
    final state = SoftBodyState(
      positions: const [0, 0, 0],
      velocities: const [0, 0, 0],
    );
    expect(state.positions.length, 3);
    expect(
      () => SoftBodyState(
        positions: const [0, 0, 0],
        velocities: const [double.nan, 0, 0],
      ),
      throwsFormatException,
    );
  });
}
