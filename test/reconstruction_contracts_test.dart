import 'package:flutter_test/flutter_test.dart';
import 'package:virxmagical/domain/reconstruction_contracts.dart';

ReconstructionFrame frame(int timestamp) => ReconstructionFrame(
  timestampNs: timestamp, rgbTimestampNs: timestamp,
  cameraPose: List<double>.filled(16, 0),
  intrinsics: const CameraIntrinsics(fx: 500, fy: 500, cx: 320, cy: 240, width: 640, height: 480),
  imageWidth: 640, imageHeight: 480,
);

void main() {
  group('ReconstructionSequence', () {
    test('accepts ordered synchronized frames', () {
      expect(() => ReconstructionSequence([frame(1), frame(2)]).validate(minimumFrames: 2), returnsNormally);
    });
    test('rejects duplicate and out-of-order timestamps', () {
      expect(() => ReconstructionSequence([frame(2), frame(2)]).validate(), throwsFormatException);
      expect(() => ReconstructionSequence([frame(3), frame(2)]).validate(), throwsFormatException);
    });
    test('rejects invalid camera intrinsics and pose dimensions', () {
      final invalid = ReconstructionFrame(timestampNs: 1, rgbTimestampNs: 1, cameraPose: [1, 2],
        intrinsics: const CameraIntrinsics(fx: 0, fy: 500, cx: 320, cy: 240, width: 640, height: 480),
        imageWidth: 640, imageHeight: 480);
      expect(() => invalid.validate(), throwsFormatException);
    });
    test('rejects mismatched depth confidence arrays', () {
      final invalid = ReconstructionFrame(timestampNs: 1, rgbTimestampNs: 1, cameraPose: List<double>.filled(16, 0),
        intrinsics: const CameraIntrinsics(fx: 500, fy: 500, cx: 320, cy: 240, width: 640, height: 480),
        imageWidth: 640, imageHeight: 480, depthMeters: [1, 2], depthConfidence: [255]);
      expect(() => invalid.validate(), throwsFormatException);
    });
  });
  test('texture artifacts require UV coordinates', () {
    final artifact = ReconstructionArtifact(uri: Uri.parse('file:///scan/model.glb'), format: 'glb',
      vertexCount: 8, triangleCount: 12, hasUv: false, hasTexture: true, hasMetricScale: true);
    expect(artifact.validate, throwsFormatException);
  });
}
