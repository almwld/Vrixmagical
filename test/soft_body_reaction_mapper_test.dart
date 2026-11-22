import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

import 'package:virxmagical/domain/soft_body_reaction_mapper.dart';

void main() {
  group('SoftBodyReactionMapper', () {
    test('keeps equal and opposite impulses at their separate contact points', () {
      final mapped = SoftBodyReactionMapper.map(
        packedForces: List<double>.filled(24, 0)
          ..[2] = 10
          ..[14] = -10,
        contacts: <SoftBodyReactionContact>[
          SoftBodyReactionContact(
            rigidBodyId: 'dynamic',
            vertexIndex: 0,
            contactSlot: 0,
            worldPoint: Vector3(1, 2, 0),
          ),
          SoftBodyReactionContact(
            rigidBodyId: 'dynamic',
            vertexIndex: 1,
            contactSlot: 0,
            worldPoint: Vector3(-1, 2, 0),
          ),
        ],
        worldTransform: Matrix4.identity(),
        deltaSeconds: 0.02,
        isDynamicBody: (_) => true,
      );

      expect(mapped, hasLength(2));
      expect(mapped[0].impulse.z, closeTo(0.2, 1e-9));
      expect(mapped[1].impulse.z, closeTo(-0.2, 1e-9));
      expect(mapped[0].worldPoint.x, 1);
      expect(mapped[1].worldPoint.x, -1);
    });

    test('rotates reaction direction but does not translate a force vector', () {
      final transform = Matrix4.identity()
        ..rotateY(math.pi / 2)
        ..setTranslation(Vector3(4, 5, 6));
      final mapped = SoftBodyReactionMapper.map(
        packedForces: <double>[0, 0, 5, ...List<double>.filled(9, 0)],
        contacts: <SoftBodyReactionContact>[
          SoftBodyReactionContact(
            rigidBodyId: 'dynamic',
            vertexIndex: 0,
            contactSlot: 0,
            worldPoint: Vector3(4, 5, 6),
          ),
        ],
        worldTransform: transform,
        deltaSeconds: 0.04,
        isDynamicBody: (_) => true,
      );

      expect(mapped, hasLength(1));
      expect(mapped.single.impulse.x, closeTo(0.2, 1e-8));
      expect(mapped.single.impulse.y, closeTo(0, 1e-8));
      expect(mapped.single.impulse.z, closeTo(0, 1e-8));
    });

    test('skips non-dynamic bodies and zero impulses', () {
      final mapped = SoftBodyReactionMapper.map(
        packedForces: <double>[0, 0, 4, ...List<double>.filled(21, 0)],
        contacts: <SoftBodyReactionContact>[
          SoftBodyReactionContact(
            rigidBodyId: 'static',
            vertexIndex: 0,
            contactSlot: 0,
            worldPoint: Vector3.zero(),
          ),
          SoftBodyReactionContact(
            rigidBodyId: 'dynamic',
            vertexIndex: 1,
            contactSlot: 0,
            worldPoint: Vector3.zero(),
          ),
        ],
        worldTransform: Matrix4.identity(),
        deltaSeconds: 1 / 60,
        isDynamicBody: (id) => id == 'dynamic',
      );

      expect(mapped, isEmpty);
    });

    test('rejects invalid time, short buffers and non-finite forces', () {
      final contact = <SoftBodyReactionContact>[
        SoftBodyReactionContact(
          rigidBodyId: 'dynamic',
          vertexIndex: 1,
          contactSlot: 0,
          worldPoint: Vector3.zero(),
        ),
      ];
      expect(
        () => SoftBodyReactionMapper.map(
          packedForces: const [0, 0, 1],
          contacts: contact,
          worldTransform: Matrix4.identity(),
          deltaSeconds: -1,
          isDynamicBody: (_) => true,
        ),
        throwsArgumentError,
      );
      expect(
        () => SoftBodyReactionMapper.map(
          packedForces: const [0, 0, 1],
          contacts: contact,
          worldTransform: Matrix4.identity(),
          deltaSeconds: 0.01,
          isDynamicBody: (_) => true,
        ),
        throwsRangeError,
      );
      expect(
        () => SoftBodyReactionMapper.map(
          packedForces: const [double.nan, 0, 1],
          contacts: <SoftBodyReactionContact>[
            SoftBodyReactionContact(
              rigidBodyId: 'dynamic',
              vertexIndex: 0,
              contactSlot: 0,
              worldPoint: Vector3.zero(),
            ),
          ],
          worldTransform: Matrix4.identity(),
          deltaSeconds: 0.01,
          isDynamicBody: (_) => true,
        ),
        throwsStateError,
      );
    });

    test('maps two rigid bodies from independent slots on one vertex', () {
      final packed = List<double>.filled(12, 0)
        ..[2] = 3
        ..[5] = -7;
      final mapped = SoftBodyReactionMapper.map(
        packedForces: packed,
        contacts: <SoftBodyReactionContact>[
          SoftBodyReactionContact(
            rigidBodyId: 'rigid-a',
            vertexIndex: 0,
            contactSlot: 0,
            worldPoint: Vector3(1, 0, 0),
          ),
          SoftBodyReactionContact(
            rigidBodyId: 'rigid-b',
            vertexIndex: 0,
            contactSlot: 1,
            worldPoint: Vector3(-1, 0, 0),
          ),
        ],
        worldTransform: Matrix4.identity(),
        deltaSeconds: 0.1,
        isDynamicBody: (_) => true,
      );

      expect(mapped, hasLength(2));
      expect(mapped[0].rigidBodyId, 'rigid-a');
      expect(mapped[0].impulse.z, closeTo(0.3, 1e-9));
      expect(mapped[1].rigidBodyId, 'rigid-b');
      expect(mapped[1].impulse.z, closeTo(-0.7, 1e-9));
    });
  });
}
