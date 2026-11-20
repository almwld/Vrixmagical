import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:virxmagical/domain/guided_path_definition.dart';

void main() {
  group('GuidedPathDefinition', () {
    GuidedPathDefinition path() => GuidedPathDefinition(
          id: 'channel-a',
          controlPoints: [
            Vector3(0, 0, 0),
            Vector3(0, 0, 1),
            Vector3(1, 0, 2),
          ],
          clearanceRadii: const [0.2, 0.2, 0.1],
          entryTolerance: 0.05,
          exitTolerance: 0.05,
        );

    test('projects to closest segment and returns normalized progress', () {
      final result = path().project(
        Vector3(0.05, 0, 0.5),
        movingRadius: 0.05,
      );
      expect(result.pathId, 'channel-a');
      expect(result.segmentIndex, 0);
      expect(result.closestPoint.x, closeTo(0, 1e-9));
      expect(result.closestPoint.z, closeTo(0.5, 1e-9));
      expect(result.progress, greaterThan(0));
      expect(result.progress, lessThan(1));
      expect(result.tangent.length, closeTo(1, 1e-9));
      expect(result.hasClearance, isTrue);
    });

    test('does not expose mutable references to validated control points', () {
      final definition = path();
      final exposedPoints = definition.controlPoints;
      exposedPoints.first.x = 99;

      final projection = definition.project(
        Vector3(0, 0, 0.5),
        movingRadius: 0.05,
      );
      expect(projection.closestPoint.x, closeTo(0, 1e-9));
      expect(projection.progress, closeTo(0.25, 1e-9));
    });

    test('rejects a body that exceeds the local clearance', () {
      final result = path().project(
        Vector3(0.19, 0, 0.5),
        movingRadius: 0.05,
      );
      expect(result.hasClearance, isFalse);
      expect(result.phase, GuidedPathPhase.outside);
    });

    test('classifies entry and exit zones', () {
      final definition = path();
      final entry = definition.project(
        Vector3.zero(),
        movingRadius: 0.05,
      );
      final exit = definition.project(
        Vector3(1, 0, 2),
        movingRadius: 0.02,
      );
      expect(entry.phase, GuidedPathPhase.entry);
      expect(exit.phase, GuidedPathPhase.exit);
    });

    test('enforces authored one-way traversal without affecting bidirectional paths', () {
      final oneWay = GuidedPathDefinition(
        id: 'one-way',
        controlPoints: [Vector3.zero(), Vector3(0, 0, 1)],
        clearanceRadii: const [0.2, 0.2],
        permittedDirection: GuidedPathDirection.forward,
      );
      final forward = oneWay.project(
        Vector3(0, 0, 0.5),
        movingRadius: 0.05,
        travelDirection: 1,
      );
      final reverse = oneWay.project(
        Vector3(0, 0, 0.5),
        movingRadius: 0.05,
        travelDirection: -1,
      );
      expect(forward.phase, GuidedPathPhase.inside);
      expect(reverse.phase, GuidedPathPhase.disallowedDirection);
      final outside = oneWay.project(
        Vector3(1, 0, 0.5),
        movingRadius: 0.05,
        travelDirection: -1,
      );
      expect(outside.phase, GuidedPathPhase.outside);
    });

    test('rejects degenerate segments and invalid clearances', () {
      expect(
        () => GuidedPathDefinition(
          id: 'bad',
          controlPoints: [Vector3.zero(), Vector3.zero()],
          clearanceRadii: const [0.1, 0.1],
        ),
        throwsFormatException,
      );
      expect(
        () => GuidedPathDefinition(
          id: 'bad',
          controlPoints: [Vector3.zero(), Vector3(0, 0, 1)],
          clearanceRadii: const [0.1, double.nan],
        ),
        throwsFormatException,
      );
    });
  });
}
