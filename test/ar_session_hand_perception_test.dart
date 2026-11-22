import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:virxmagical/domain/captured_frame.dart';
import 'package:virxmagical/services/ar_session_hand_perception.dart';

void main() {
  final intrinsics = CameraIntrinsics(
    fx: 100,
    fy: 100,
    cx: 2,
    cy: 2,
    width: 5,
    height: 5,
  );
  final depth = DepthFrame(
    valuesMeters: Float32List(25)..fillRange(0, 25, 2),
    confidence: Uint8List(25)..fillRange(0, 25, 255),
    width: 5,
    height: 5,
    frameTimestampNs: 1000000,
    imageTimestampNs: 1000000,
    intrinsics: intrinsics,
  );
  final identityPose = Float64List.fromList([
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1,
  ]);

  test('projects a normalized hand landmark through depth into AR world', () {
    final point = const ArDepthProjector().project(
      normalizedPoint: const Offset(0.5, 0.5),
      rgbIntrinsics: intrinsics,
      depth: depth,
      cameraPose: identityPose,
    );

    expect(point, isNotNull);
    expect(point!.x, closeTo(0, 1e-6));
    expect(point.y, closeTo(0, 1e-6));
    expect(point.z, closeTo(-2, 1e-6));
  });

  test('applies camera world pose after depth back-projection', () {
    final translatedPose = Float64List.fromList([
      1, 0, 0, 0,
      0, 1, 0, 0,
      0, 0, 1, 0,
      3, 4, 5, 1,
    ]);
    final point = const ArDepthProjector().project(
      normalizedPoint: const Offset(0.5, 0.5),
      rgbIntrinsics: intrinsics,
      depth: depth,
      cameraPose: translatedPose,
    );

    expect(point, isNotNull);
    expect(point!.x, closeTo(3, 1e-6));
    expect(point.y, closeTo(4, 1e-6));
    expect(point.z, closeTo(3, 1e-6));
  });

  test('returns no world contact when depth is unavailable or invalid', () {
    expect(
      const ArDepthProjector().project(
        normalizedPoint: const Offset(0.5, 0.5),
        rgbIntrinsics: intrinsics,
        depth: null,
        cameraPose: identityPose,
      ),
      isNull,
    );
    expect(
      const ArDepthProjector().project(
        normalizedPoint: const Offset(2, 0.5),
        rgbIntrinsics: intrinsics,
        depth: depth,
        cameraPose: identityPose,
      ),
      isNull,
    );
  });
}
