import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:virxmagical/features/hand/hand_gesture_math.dart';
import 'package:virxmagical/services/ar_hand_xpbd_bridge.dart';
import 'package:virxmagical/services/ar_session_hand_perception.dart';
import 'package:vrix_soft_body/vrix_soft_body.dart';

class _FakeXpbdDriver implements XpbdPointTargetDriver {
  _FakeXpbdDriver(this.positions);

  final List<double> positions;
  final Map<int, List<double>> targets = <int, List<double>>{};
  final List<int> cleared = <int>[];

  @override
  SoftBodyState readState() => SoftBodyState(
        positions: positions,
        velocities: List<double>.filled(positions.length, 0),
      );

  @override
  void setPointTarget({
    required int vertexIndex,
    required List<double> targetObjectPosition,
    double compliance = 0,
  }) {
    targets[vertexIndex] = List<double>.of(targetObjectPosition);
  }

  @override
  void clearPointTarget({required int vertexIndex}) {
    targets.remove(vertexIndex);
    cleared.add(vertexIndex);
  }
}

ArHandObservation _observation({
  required bool pinching,
  Vector3? indexTip,
}) {
  final hand = ArTrackedHand(
    handedness: 'Left',
    landmarks: const <Offset>[],
    pinchRatio: pinching ? 0.1 : 0.8,
    isPinching: pinching,
    pinchEvent: pinching ? PinchEvent.pressed : PinchEvent.released,
    worldLandmarks: indexTip == null ? const {} : {8: indexTip},
  );
  return ArHandObservation(
    frameTimestampNs: 1000000,
    rgbTimestampNs: 1000000,
    cameraPose: Float64List(16),
    hands: [hand],
    depthAvailable: indexTip != null,
  );
}

void main() {
  test('pinch drives the nearest XPBD vertex in object-local metres', () {
    final driver = _FakeXpbdDriver([
      0, 0, 0,
      1, 0, 0,
      0, 1, 0,
      0, 0, 1,
    ]);
    final bridge = ArHandXpbdBridge(driver: driver);
    final worldFromObject = Matrix4.translationValues(10, 0, 0);

    bridge.update(
      observation: _observation(
        pinching: true,
        indexTip: Vector3(10.04, 0.02, 0),
      ),
      worldFromObject: worldFromObject,
    );

    expect(bridge.activeTargets['Left'], 0);
    expect(driver.targets[0]![0], closeTo(0.04, 1e-6));
    expect(driver.targets[0]![1], closeTo(0.02, 1e-6));
  });

  test('release clears the persistent XPBD point target', () {
    final driver = _FakeXpbdDriver([
      0, 0, 0,
      1, 0, 0,
      0, 1, 0,
      0, 0, 1,
    ]);
    final bridge = ArHandXpbdBridge(driver: driver);
    final transform = Matrix4.identity();

    bridge.update(
      observation: _observation(
        pinching: true,
        indexTip: Vector3(0.01, 0.01, 0),
      ),
      worldFromObject: transform,
    );
    bridge.update(
      observation: _observation(pinching: false),
      worldFromObject: transform,
    );

    expect(bridge.activeTargets, isEmpty);
    expect(driver.targets, isEmpty);
    expect(driver.cleared, contains(0));
  });

  test('tracking loss clears targets and distant hands cannot grab the mesh', () {
    final driver = _FakeXpbdDriver([
      0, 0, 0,
      1, 0, 0,
      0, 1, 0,
      0, 0, 1,
    ]);
    final bridge = ArHandXpbdBridge(
      driver: driver,
      maximumTargetDistanceMeters: 0.1,
    );

    bridge.update(
      observation: _observation(
        pinching: true,
        indexTip: Vector3(5, 5, 5),
      ),
      worldFromObject: Matrix4.identity(),
    );
    expect(bridge.activeTargets, isEmpty);

    bridge.update(
      observation: ArHandObservation(
        frameTimestampNs: 2000000,
        rgbTimestampNs: 2000000,
        cameraPose: Float64List(16),
        hands: const [],
        depthAvailable: false,
      ),
      worldFromObject: Matrix4.identity(),
    );
    expect(driver.targets, isEmpty);
  });
}
