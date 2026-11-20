import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

import 'package:virxmagical/domain/soft_body_scene_runtime.dart';

void main() {
  group('SoftBodyRenderFrame', () {
    test('keeps a renderer-ready immutable surface snapshot', () {
      final positions = <double>[
        0, 0, 0,
        1, 0, 0,
        0, 1, 0,
        0, 0, 1,
      ];
      final velocities = List<double>.filled(12, 0);
      final triangles = <int>[0, 2, 1, 0, 1, 3, 1, 2, 3, 2, 0, 3];
      final frame = SoftBodyRenderFrame(
        frameNumber: 1,
        positions: positions,
        velocities: velocities,
        surfaceTriangleIndices: triangles,
        worldTransform: Matrix4.identity(),
      );

      positions[0] = 99;
      triangles[0] = 99;

      expect(frame.vertexCount, 4);
      expect(frame.triangleCount, 4);
      expect(frame.positions.first, 0);
      expect(frame.surfaceTriangleIndices.first, 0);
    });

    test('rejects mismatched or out-of-range render buffers', () {
      expect(
        () => SoftBodyRenderFrame(
          frameNumber: 0,
          positions: const [0, 0, 0, 1, 0, 0, 0, 1, 0],
          velocities: const [0, 0, 0],
          surfaceTriangleIndices: const [0, 1, 2],
          worldTransform: Matrix4.identity(),
        ),
        throwsFormatException,
      );
      expect(
        () => SoftBodyRenderFrame(
          frameNumber: 0,
          positions: const [0, 0, 0, 1, 0, 0, 0, 1, 0],
          velocities: const [0, 0, 0, 0, 0, 0, 0, 0, 0],
          surfaceTriangleIndices: const [0, 1, 3],
          worldTransform: Matrix4.identity(),
        ),
        throwsFormatException,
      );
    });
  });
}
