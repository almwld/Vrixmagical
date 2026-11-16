import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:virxmagical/domain/captured_frame.dart';

Float64List identityPose() => Float64List.fromList([
      1, 0, 0, 0,
      0, 1, 0, 0,
      0, 0, 1, 0,
      0, 0, 0, 1,
    ]);

CapturedFrame makeFrame({
  int rgbTimestamp = 42,
  int depthTimestamp = 42,
  Float64List? pose,
  double fx = 2,
  int imageRotationDegrees = 0,
}) {
  const depthIntrinsics = CameraIntrinsics(
    fx: 1,
    fy: 1,
    cx: .5,
    cy: .5,
    width: 2,
    height: 2,
  );
  return CapturedFrame(
    rgbBytes: Uint8List.fromList([1, 2, 3]),
    rgbTimestampNs: rgbTimestamp,
    rgbIntrinsics: CameraIntrinsics(
      fx: fx,
      fy: fx,
      cx: 1,
      cy: 1,
      width: 4,
      height: 4,
    ),
    cameraPose: pose ?? identityPose(),
    trackingState: VrixTrackingState.tracking,
    depthSupport: VrixDepthSupport.automatic,
    depth: DepthFrame(
      valuesMeters: Float32List.fromList([1, 1, 1, 1]),
      confidence: Uint8List.fromList([255, 255, 255, 255]),
      width: 2,
      height: 2,
      timestampNs: depthTimestamp,
      intrinsics: depthIntrinsics,
    ),
    imageRotationDegrees: imageRotationDegrees,
  );
}

void main() {
  group('CapturedFrame contract', () {
    test('accepts a synchronized RGB-D frame with a rigid identity pose', () {
      expect(
        () => makeFrame().validate(requireDepth: true),
        returnsNormally,
      );
    });

    test('rejects RGB and depth from different ARCore frames', () {
      expect(
        () => makeFrame(rgbTimestamp: 42, depthTimestamp: 43)
            .validate(requireDepth: true),
        throwsFormatException,
      );
    });

    test('rejects non-orthonormal camera rotation', () {
      final invalid = identityPose()..[0] = 2;
      expect(
        () => makeFrame(pose: invalid).validate(),
        throwsFormatException,
      );
    });

    test('rejects non-positive focal length', () {
      expect(
        () => makeFrame(fx: 0).validate(),
        throwsFormatException,
      );
    });

    test('rejects rotated RGB until an explicit registration transform exists', () {
      expect(
        () => makeFrame(imageRotationDegrees: 90).validate(requireDepth: true),
        throwsFormatException,
      );
    });

    test('rejects paused tracking frames', () {
      final captured = makeFrame();
      final paused = CapturedFrame(
        rgbBytes: captured.rgbBytes,
        rgbTimestampNs: captured.rgbTimestampNs,
        rgbIntrinsics: captured.rgbIntrinsics,
        cameraPose: captured.cameraPose,
        trackingState: VrixTrackingState.paused,
        depthSupport: VrixDepthSupport.automatic,
        depth: captured.depth,
      );
      expect(
        () => paused.validate(requireDepth: true),
        throwsFormatException,
      );
    });
  });

  group('Depth alignment and point cloud', () {
    test('projects depth samples into RGB pixels and preserves confidence', () {
      final captured = makeFrame();
      final aligned = const DepthAligner().alignDepthAndConfidence(
        captured.depth!,
        captured.rgbIntrinsics,
      );
      expect(aligned.values.length, 16);
      expect(aligned.values[0], 1);
      expect(aligned.values[2], 1);
      expect(aligned.values[8], 1);
      expect(aligned.values[10], 1);
      expect(aligned.confidence[0], 255);
    });

    test('backprojects masked depth into world-space points', () {
      final captured = makeFrame();
      final mask = Uint8List(16)..fillRange(0, 16, 255);
      final points = const MaskedPointCloudBuilder().build(
        frame: captured,
        rgbMask: mask,
        pixelStride: 1,
        minimumConfidence: .5,
      );
      expect(points.length, 4);
      expect(points.first, isA<Vector3>());
      expect(points.first.z, closeTo(-1, 1e-6));
    });

    test('drops low-confidence samples before point-cloud fusion', () {
      final captured = makeFrame();
      captured.depth!.confidence[0] = 10;
      final points = const MaskedPointCloudBuilder().build(
        frame: captured,
        rgbMask: Uint8List(16)..fillRange(0, 16, 255),
        pixelStride: 1,
        minimumConfidence: .5,
      );
      expect(points.length, 3);
    });

    test('aligns a lower-resolution segmentation mask to the RGB grid', () {
      final aligned = const SegmentationMaskAligner().alignNearestNeighbor(
        mask: Uint8List.fromList([255, 0, 0, 255]),
        maskWidth: 2,
        maskHeight: 2,
        rgbWidth: 4,
        rgbHeight: 4,
      );
      expect(aligned.length, 16);
      expect(aligned[0], 255);
      expect(aligned[3], 0);
      expect(aligned[12], 0);
      expect(aligned[15], 255);
    });

    test('voxel fusion averages points in the same spatial cell', () {
      final fused = const PointCloudVoxelFusion().downsample(
        [
          Vector3(0.001, 0, 0),
          Vector3(0.004, 0, 0),
          Vector3(0.02, 0, 0),
        ],
        voxelSizeMeters: .01,
      );
      expect(fused.length, 2);
      expect(fused.first.x, closeTo(.0025, 1e-6));
    });

    test('rejects masks that do not match RGB dimensions', () {
      expect(
        () => const MaskedPointCloudBuilder().build(
          frame: makeFrame(),
          rgbMask: Uint8List(4),
        ),
        throwsFormatException,
      );
    });
  });
}
