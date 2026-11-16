import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

import 'package:virxmagical/services/physics_scene_service.dart';

void main() {
  group('PhysicsSceneService', () {
    late PhysicsSceneService physics;

    setUp(() {
      physics = PhysicsSceneService(maxSubSteps: 5);
    });

    tearDown(() {
      physics.dispose();
    });

    test('creates and removes rigid bodies with stable identities', () {
      final transform = Matrix4.identity()
        ..setTranslation(Vector3(0, 1, 0));
      physics.addStaticBox(
        id: 'floor',
        worldTransform: transform,
        halfExtents: Vector3(2, 0.05, 2),
      );
      physics.addDynamicBox(
        id: 'crate',
        worldTransform: transform,
        halfExtents: Vector3.all(0.25),
      );

      expect(physics.bodyCount, 2);
      physics.removeBody('crate');
      expect(physics.bodyCount, 1);
    });

    test('bounds fixed-step catch-up after long frames', () {
      expect(physics.advance(1 / 30), 2);
      expect(physics.advance(10), 5);
    });

    test('rejects invalid time, collider dimensions and material values', () {
      final transform = Matrix4.identity();
      expect(() => physics.advance(double.nan), throwsArgumentError);
      expect(
        () => physics.addDynamicBox(
          id: 'bad-size',
          worldTransform: transform,
          halfExtents: Vector3(0, 1, 1),
        ),
        throwsArgumentError,
      );
      expect(
        () => physics.addStaticBox(
          id: 'bad-friction',
          worldTransform: transform,
          halfExtents: Vector3.all(1),
          friction: 1.5,
        ),
        throwsArgumentError,
      );
    });

    test('rejects duplicate identities and non-finite transforms', () {
      final transform = Matrix4.identity();
      physics.addDynamicBox(
        id: 'box',
        worldTransform: transform,
        halfExtents: Vector3.all(0.5),
      );
      expect(
        () => physics.addDynamicBox(
          id: 'box',
          worldTransform: transform,
          halfExtents: Vector3.all(0.5),
        ),
        throwsStateError,
      );
      final invalid = Matrix4.identity()..setEntry(0, 0, double.nan);
      expect(
        () => physics.addDynamicBox(
          id: 'invalid-transform',
          worldTransform: invalid,
          halfExtents: Vector3.all(0.5),
        ),
        throwsArgumentError,
      );
    });

    test('disposal is idempotent and rejects further simulation', () {
      physics.dispose();
      physics.dispose();
      expect(physics.isDisposed, isTrue);
      expect(() => physics.advance(1 / 60), throwsStateError);
    });
  });
}
