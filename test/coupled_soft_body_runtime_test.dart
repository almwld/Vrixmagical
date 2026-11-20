import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

import 'package:virxmagical/domain/soft_body_scene_runtime.dart';
import 'package:virxmagical/services/object_scan_reconstruction_service.dart';
import 'package:virxmagical/services/physics_scene_service.dart';
import 'package:virxmagical/services/voxel_mesh_reconstruction.dart';
import 'package:virxmagical/services/voxel_tetrahedralizer.dart';

void main() {
  group('VrixSoftBodySceneRuntime', () {
    late Directory temporaryDirectory;

    setUp(() async {
      temporaryDirectory =
          await Directory.systemTemp.createTemp('vrix-coupled-runtime-');
    });

    tearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('advances XPBD and reports Jolt sensor-proxy contacts', () {
      final points = <Vector3>[
        for (var x = 0; x < 2; x++)
          for (var y = 0; y < 2; y++)
            for (var z = 0; z < 2; z++)
              Vector3(x * 0.04, y * 0.04, z * 0.04),
      ];
      final tetrahedralization = const VoxelTetrahedralizer().tetrahedralize(
        points,
        voxelSizeMeters: 0.04,
        maximumOccupiedVoxels: 32,
        maximumTetrahedra: 256,
      );
      final surface = ReconstructedVoxelMesh(
        vertices: tetrahedralization.surfaceVertices,
        triangleIndices: tetrahedralization.surfaceTriangleIndices,
        voxelSizeMeters: 0.04,
      );
      final reconstruction = ObjectScanReconstructionResult(
        mesh: surface,
        tetrahedralization: tetrahedralization,
        glbFile: File('${temporaryDirectory.path}/unused.glb'),
        inputViewCount: 3,
        inputPointCount: points.length,
        voxelPointCount: points.length,
      );
      final physics = PhysicsSceneService();
      final runtime = VrixSoftBodySceneRuntime.fromReconstruction(
        reconstruction: reconstruction,
        scene: physics,
        objectId: 'runtime-test',
        worldTransform: Matrix4.identity(),
        maxContactDistance: 0.5,
      );

      try {
        physics.addDynamicSphere(
          id: 'runtime-probe',
          worldTransform: Matrix4.identity()
            ..setTranslation(Vector3(0, 0.04, 0)),
          radius: 0.12,
          mass: 0.2,
          restitution: 0,
        );

        physics.advance(1 / 60);
        final directOverlaps = physics.overlapBody('soft:runtime-test');
        final directProbeHit = directOverlaps.firstWhere(
          (hit) => hit.bodyId == 'runtime-probe',
        );
        expect(directProbeHit.normal.length2, greaterThan(1e-8));
        expect(
          directProbeHit.point.storage.every((value) => value.isFinite),
          isTrue,
        );

        var frame = runtime.advance(1 / 60);
        final firstFrameContactCount = runtime.activeContactCount;
        for (var i = 1; i < 6; i++) {
          frame = runtime.advance(1 / 60);
        }

        expect(frame.vertexCount, tetrahedralization.vertexCount);
        expect(frame.triangleCount, tetrahedralization.mesh.triangleCount);
        expect(runtime.coupledSteps, greaterThan(0));
        expect(firstFrameContactCount, greaterThan(0));
        // Contact presence alone is not proof of two-way coupling: require
        // XPBD's measured reaction to be emitted as a point impulse to Jolt.
        expect(runtime.lastAppliedReactionCount, greaterThan(0));
        expect(runtime.lastAppliedReactionImpulse.length2, greaterThan(1e-12));
        expect(physics.isDynamicBody('runtime-probe'), isTrue);
        expect(physics.isDynamicBody('soft:runtime-test'), isFalse);
      } finally {
        runtime.dispose();
        physics.dispose();
      }
    });
  });
}
