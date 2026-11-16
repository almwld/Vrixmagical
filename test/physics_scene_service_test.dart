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

    test('supports sphere and capsule rigid-body colliders', () {
      final transform = Matrix4.identity();
      physics.addDynamicSphere(
        id: 'sphere',
        worldTransform: transform,
        radius: 0.2,
      );
      physics.addDynamicCapsule(
        id: 'capsule',
        worldTransform: transform,
        radius: 0.15,
        halfHeight: 0.35,
      );
      expect(physics.bodyCount, 2);
    });

    test('Jolt resolves rigid-body contact and buffers contact events', () {
      physics.addStaticBox(
        id: 'ground',
        worldTransform: Matrix4.identity()
          ..setTranslation(Vector3(0, -0.05, 0)),
        halfExtents: Vector3(2, 0.05, 2),
      );
      physics.addDynamicSphere(
        id: 'falling-ball',
        worldTransform: Matrix4.identity()
          ..setTranslation(Vector3(0, 1.5, 0)),
        radius: 0.2,
      );

      for (var i = 0; i < 240; i++) {
        physics.advance(1 / 60);
      }

      final settled = physics.bodyWorldTransform('falling-ball').getTranslation();
      expect(settled.y, closeTo(0.2, 0.04));
      final events = physics.drainEvents();
      expect(events.any((event) => event.isContactBegin), isTrue);
    });

    test('batch reads active transforms and supports Jolt raycasts', () {
      physics.addStaticBox(
        id: 'query-floor',
        worldTransform: Matrix4.identity(),
        halfExtents: Vector3(2, 0.1, 2),
      );
      physics.addDynamicBox(
        id: 'query-box',
        worldTransform: Matrix4.identity()
          ..setTranslation(Vector3(0, 1, 0)),
        halfExtents: Vector3.all(0.2),
      );

      expect(physics.activeBodyTransforms().containsKey('query-box'), isTrue);
      final hits = physics.raycast(
        Vector3(0, 2, 0),
        Vector3(0, -4, 0),
        allHits: true,
      );
      expect(hits, isNotEmpty);
      expect(hits.first.bodyId, 'query-box');
    });

    test('supports constraints and preserves joint graph during body teleports', () {
      physics.addDynamicBox(
        id: 'joint-a',
        worldTransform: Matrix4.identity()
          ..setTranslation(Vector3(-0.5, 2, 0)),
        halfExtents: Vector3.all(0.2),
      );
      physics.addDynamicBox(
        id: 'joint-b',
        worldTransform: Matrix4.identity()
          ..setTranslation(Vector3(0.5, 2, 0)),
        halfExtents: Vector3.all(0.2),
      );
      physics.createJoint(
        id: 'hinge',
        bodyA: 'joint-a',
        bodyB: 'joint-b',
        kind: PhysicsJointKind.hinge,
        pointA: Vector3.zero(),
        pointB: Vector3.zero(),
        axis: Vector3(0, 1, 0),
        normal: Vector3(1, 0, 0),
        lowerLimit: -0.75,
        upperLimit: 0.75,
      );

      expect(physics.jointCount, 1);
      physics.setBodyWorldTransform(
        'joint-a',
        Matrix4.identity()..setTranslation(Vector3(-0.25, 2, 0)),
      );
      expect(physics.jointCount, 1);
      expect(
        physics.bodyWorldTransform('joint-a').getTranslation().x,
        closeTo(-0.25, 0.001),
      );
      physics.setJointEnabled('hinge', false);
      physics.setJointMotor(
        'hinge',
        motor: PhysicsJointMotor.velocity,
        target: 0.2,
      );
      expect(physics.jointValue('hinge'), isNotNull);
      physics.removeJoint('hinge');
      expect(physics.jointCount, 0);
    });

    test('supports dynamic convex hulls and static triangle meshes', () {
      physics.addDynamicConvexHull(
        id: 'tetra',
        worldTransform: Matrix4.identity()
          ..setTranslation(Vector3(0, 2, 0)),
        vertices: <Vector3>[
          Vector3(0, 0.2, 0),
          Vector3(-0.2, -0.2, 0.2),
          Vector3(0.2, -0.2, 0.2),
          Vector3(0, -0.2, -0.2),
        ],
      );
      physics.addStaticMesh(
        id: 'mesh-floor',
        worldTransform: Matrix4.identity(),
        vertices: <Vector3>[
          Vector3(-1, 0, -1),
          Vector3(1, 0, -1),
          Vector3(1, 0, 1),
          Vector3(-1, 0, 1),
        ],
        triangleIndices: <int>[0, 2, 1, 0, 3, 2],
      );
      expect(physics.bodyCount, 2);
    });

    test('supports kinematic motion, impulses and force application', () {
      physics.addKinematicBox(
        id: 'moving-platform',
        worldTransform: Matrix4.identity(),
        halfExtents: Vector3(0.5, 0.05, 0.5),
      );
      physics.moveKinematic(
        'moving-platform',
        Matrix4.identity()..setTranslation(Vector3(1, 0, 0)),
        deltaSeconds: 1 / 60,
      );
      physics.advance(1 / 60);
      expect(
        physics.bodyWorldTransform('moving-platform').getTranslation().x,
        closeTo(1, 0.05),
      );

      physics.addDynamicSphere(
        id: 'impulse-ball',
        worldTransform: Matrix4.identity(),
        radius: 0.15,
      );
      physics.applyImpulse('impulse-ball', Vector3(0, 1, 0));
      physics.addForce('impulse-ball', Vector3(1, 0, 0));
      for (var i = 0; i < 30; i++) {
        physics.advance(1 / 60);
      }
      final moved = physics.bodyWorldTransform('impulse-ball').getTranslation();
      expect(moved.y, greaterThan(0.05));
      expect(moved.x, greaterThan(0));
    });

    test('bounds fixed-step catch-up after long frames', () {
      expect(physics.advance(1 / 30), 2);
      expect(physics.advance(10), 5);
    });

    test('rejects invalid time, collider dimensions and material values', () {
      final transform = Matrix4.identity();
      expect(() => physics.advance(double.nan), throwsArgumentError);
      expect(
        () => physics.addDynamicSphere(
          id: 'bad-radius',
          worldTransform: transform,
          radius: double.infinity,
        ),
        throwsArgumentError,
      );
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
