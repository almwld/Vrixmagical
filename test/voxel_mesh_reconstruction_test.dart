import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:virxmagical/services/voxel_mesh_reconstruction.dart';

void main() {
  group('VoxelMeshReconstructor', () {
    test('creates closed exposed faces for a dense 2x2x2 voxel block', () {
      final points = <Vector3>[
        for (var x = 0; x < 2; x++)
          for (var y = 0; y < 2; y++)
            for (var z = 0; z < 2; z++)
              Vector3(x + .5, y + .5, z + .5),
      ];
      final mesh = const VoxelMeshReconstructor().reconstruct(
        points,
        voxelSizeMeters: 1,
      );

      expect(mesh.vertices.length, 96);
      expect(mesh.triangleCount, 48);
      mesh.validate();
    });

    test('rejects sparse or over-budget point clouds instead of emitting invalid geometry', () {
      expect(
        () => const VoxelMeshReconstructor().reconstruct(
          [Vector3.zero(), Vector3(1, 0, 0), Vector3(0, 1, 0)],
          voxelSizeMeters: 1,
        ),
        throwsStateError,
      );
      expect(
        () => const VoxelMeshReconstructor().reconstruct(
          [for (var i = 0; i < 20; i++) Vector3(i.toDouble(), 0, 0)],
          voxelSizeMeters: 1,
          maximumOccupiedVoxels: 8,
        ),
        throwsStateError,
      );
    });

    test('exports a binary glTF with a valid GLB v2 header', () async {
      final points = <Vector3>[
        for (var x = 0; x < 2; x++)
          for (var y = 0; y < 2; y++)
            for (var z = 0; z < 2; z++)
              Vector3(x + .5, y + .5, z + .5),
      ];
      final mesh = const VoxelMeshReconstructor().reconstruct(points, voxelSizeMeters: 1);
      final directory = await Directory.systemTemp.createTemp('vrix-glb-');
      try {
        final file = await mesh.exportGlb(File('${directory.path}/mesh.glb'));
        final bytes = await file.readAsBytes();
        expect(bytes.length, greaterThan(28));
        expect(bytes[0], 0x67);
        expect(bytes[1], 0x6c);
        expect(bytes[2], 0x54);
        expect(bytes[3], 0x46);
        expect(bytes[4], 2);
        expect(bytes[5], 0);
        expect(bytes[6], 0);
        expect(bytes[7], 0);
        final data = ByteData.sublistView(bytes);
        expect(data.getUint32(8, Endian.little), bytes.length);
      } finally {
        await directory.delete(recursive: true);
      }
    });
  });
}
