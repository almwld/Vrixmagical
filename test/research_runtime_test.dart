import 'package:flutter_test/flutter_test.dart';
import 'package:virxmagical/services/research_runtime.dart';

void main() {
  group('shared scene interaction', () {
    test('two-hand transform rejects coincident points and computes midpoint', () {
      expect(TwoHandTransform.fromPoints(const Vec3.zero(), const Vec3.zero()), isNull);
      final transform = TwoHandTransform.fromPoints(const Vec3(0, 0, 0), const Vec3(2, 0, 0))!;
      expect(transform.midpoint.x, 1);
      expect(transform.distance, 2);
      expect(transform.applyScale(const Vec3.one(), 1).x, 2);
    });

    test('frame gate rejects overlap and recovers stale requests safely', () {
      final gate = FrameRequestGate(timeout: const Duration(seconds: 1));
      final start = DateTime.utc(2026, 1, 1);
      final generation = gate.tryStart(start)!;
      expect(gate.tryStart(start), isNull);
      expect(gate.recoverIfStale(start.add(const Duration(seconds: 2))), isTrue);
      expect(gate.complete(generation), isFalse);
      expect(gate.tryStart(start.add(const Duration(seconds: 2))), isNotNull);
    });

    test('performance governor degrades only after sustained slow frames', () {
      final governor = AdaptivePerformanceGovernor();
      for (var i = 0; i < 11; i++) {
        governor.recordFrame(const Duration(milliseconds: 60));
      }
      expect(governor.tier, PerformanceTier.balanced);
      governor.recordFrame(const Duration(milliseconds: 60));
      expect(governor.tier, PerformanceTier.low);
    });
  });

  group('fixed step physics', () {
    test('uses bounded fixed steps and applies gravity and impulses', () {
      final physics = FixedStepPhysics();
      physics.addBody(PhysicsBody(objectId: 'cube', position: const Vec3.zero()));
      physics.applyImpulse('cube', const Vec3(1, 0, 0));
      expect(physics.advance(1 / 30), 2);
      final body = physics.bodies.single;
      expect(body.position.x, closeTo(1 / 30, 1e-6));
      expect(body.position.y, lessThan(0));
      expect(physics.advance(1), 5);
    });

    test('rejects invalid bodies and time deltas', () {
      final physics = FixedStepPhysics();
      expect(
        () => physics.addBody(PhysicsBody(objectId: '', position: const Vec3.zero())),
        throwsArgumentError,
      );
      expect(() => physics.advance(-1), throwsArgumentError);
    });
  });

  group('capture and constrained scene commands', () {
    test('capture manifest enforces pose shape and monotonic timestamps', () {
      final manifest = CaptureManifest(sessionId: 'session-1');
      final pose = List<double>.filled(16, 0)..[0] = 1;
      manifest.add(CaptureFrame(path: '/frame-1.jpg', timestampMicros: 10, cameraPose: pose));
      expect(
        () => manifest.add(CaptureFrame(path: '/frame-2.jpg', timestampMicros: 10, cameraPose: pose)),
        throwsStateError,
      );
      expect(manifest.frames, hasLength(1));
    });

    test('voice command parser allows only known object ids and safe verbs', () {
      final ids = {'lamp_1'};
      expect(SceneCommandParser.parse('hide lamp_1', ids)?.type, SceneCommandType.hide);
      expect(SceneCommandParser.parse('delete lamp_1', ids)?.requiresConfirmation, isTrue);
      expect(SceneCommandParser.parse('delete unknown', ids), isNull);
      expect(SceneCommandParser.parse('open settings', ids), isNull);
    });
  });

  test('scene registry enforces identity and consequential-action confirmation', () {
    final registry = SceneObjectRegistry();
    registry.register(const SceneObject(id: 'lamp_1', position: Vec3.zero()));
    expect(() => registry.register(const SceneObject(id: 'lamp_1', position: Vec3.zero())), throwsStateError);
    expect(registry.apply(const SceneCommand(type: SceneCommandType.hide, objectId: 'lamp_1')), isTrue);
    expect(registry['lamp_1']!.visible, isFalse);
    const delete = SceneCommand(type: SceneCommandType.delete, objectId: 'lamp_1', requiresConfirmation: true);
    expect(registry.apply(delete), isFalse);
    expect(registry['lamp_1'], isNotNull);
    expect(registry.apply(delete, confirmed: true), isTrue);
    expect(registry['lamp_1'], isNull);
  });

  test('capability report does not claim unimplemented native features', () {
    const capabilities = ResearchRuntimeCapabilities();
    expect(capabilities.edgeSam.state, RuntimeCapabilityState.fallback);
    expect(capabilities.depth.state, RuntimeCapabilityState.notProbed);
    expect(capabilities.reconstruction.state, RuntimeCapabilityState.unsupported);
    expect(capabilities.voice.state, RuntimeCapabilityState.unsupported);
  });
}
