import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart';

enum VrixTrackingState { tracking, paused, stopped }
enum VrixDepthSupport { automatic, rawOnly, unsupported, notChecked }

/// Camera calibration in pixel units for one specific image stream.
class CameraIntrinsics {
  const CameraIntrinsics({
    required this.fx,
    required this.fy,
    required this.cx,
    required this.cy,
    required this.width,
    required this.height,
  });

  final double fx;
  final double fy;
  final double cx;
  final double cy;
  final int width;
  final int height;

  void validate() {
    if (!fx.isFinite || !fy.isFinite || fx <= 0 || fy <= 0) {
      throw const FormatException('Camera focal lengths must be finite and positive.');
    }
    if (width <= 0 ||
        height <= 0 ||
        !cx.isFinite ||
        !cy.isFinite ||
        cx < 0 ||
        cy < 0 ||
        cx >= width ||
        cy >= height) {
      throw const FormatException('Camera principal point or image dimensions are invalid.');
    }
  }

  Map<String, Object> toJson() => {
        'fx': fx,
        'fy': fy,
        'cx': cx,
        'cy': cy,
        'width': width,
        'height': height,
      };
}

/// Depth and confidence sampled from one ARCore frame timestamp.
class DepthFrame {
  DepthFrame({
    required this.valuesMeters,
    required this.confidence,
    required this.width,
    required this.height,
    required this.timestampNs,
    required this.intrinsics,
  });

  final Float32List valuesMeters;
  final Uint8List confidence;
  final int width;
  final int height;
  final int timestampNs;
  final CameraIntrinsics intrinsics;

  void validate() {
    if (width <= 0 ||
        height <= 0 ||
        valuesMeters.length != width * height ||
        confidence.length != width * height) {
      throw const FormatException('Depth and confidence buffers must match depth dimensions.');
    }
    if (timestampNs <= 0) {
      throw const FormatException('Depth timestamp must be a positive ARCore nanosecond timestamp.');
    }
    if (intrinsics.width != width || intrinsics.height != height) {
      throw const FormatException('Depth intrinsics must describe the depth image dimensions.');
    }
    intrinsics.validate();
    for (final value in valuesMeters) {
      if (!value.isFinite || value < 0) {
        throw const FormatException('Depth values must be finite, non-negative meters.');
      }
    }
  }
}

/// A single synchronized RGB-D observation from one ARCore Frame.
/// cameraPose is a column-major world-from-camera 4x4 matrix in meters.
class CapturedFrame {
  CapturedFrame({
    required this.rgbBytes,
    required this.rgbTimestampNs,
    required this.rgbIntrinsics,
    required this.cameraPose,
    required this.trackingState,
    required this.depthSupport,
    this.depth,
    this.imageRotationDegrees = 0,
  });

  final Uint8List rgbBytes;
  final int rgbTimestampNs;
  final CameraIntrinsics rgbIntrinsics;
  final Float64List cameraPose;
  final VrixTrackingState trackingState;
  final VrixDepthSupport depthSupport;
  final DepthFrame? depth;
  final int imageRotationDegrees;

  int get rgbWidth => rgbIntrinsics.width;
  int get rgbHeight => rgbIntrinsics.height;

  void validate({bool requireDepth = false}) {
    if (rgbBytes.isEmpty || rgbTimestampNs <= 0) {
      throw const FormatException('RGB payload and positive frame timestamp are required.');
    }
    rgbIntrinsics.validate();
    if (imageRotationDegrees % 90 != 0) {
      throw const FormatException('Image rotation must be a multiple of 90 degrees.');
    }
    _validateRigidPose(cameraPose);
    if (trackingState != VrixTrackingState.tracking) {
      throw const FormatException('Only fully tracking ARCore frames may enter reconstruction.');
    }
    if (requireDepth && depth == null) {
      throw const FormatException('This reconstruction path requires a depth frame.');
    }
    if (depth != null) {
      depth!.validate();
      if (depth!.timestampNs != rgbTimestampNs) {
        throw const FormatException(
          'RGB and Depth must originate from the exact same ARCore frame timestamp.',
        );
      }
      if (depthSupport == VrixDepthSupport.unsupported ||
          depthSupport == VrixDepthSupport.notChecked) {
        throw const FormatException(
          'Depth payload conflicts with the reported device depth capability.',
        );
      }
    }
  }

  static void _validateRigidPose(Float64List matrix) {
    if (matrix.length != 16 || matrix.any((value) => !value.isFinite)) {
      throw const FormatException('Camera pose must be a finite 4x4 matrix.');
    }
    const epsilon = 1e-3;
    if (matrix[3].abs() > epsilon ||
        matrix[7].abs() > epsilon ||
        matrix[11].abs() > epsilon ||
        (matrix[15] - 1).abs() > epsilon) {
      throw const FormatException('Camera pose must be an affine rigid transform.');
    }

    // Matrix4 storage is column-major. Its first three columns form rotation.
    final x = Vector3(matrix[0], matrix[1], matrix[2]);
    final y = Vector3(matrix[4], matrix[5], matrix[6]);
    final z = Vector3(matrix[8], matrix[9], matrix[10]);
    if ((x.length2 - 1).abs() > epsilon ||
        (y.length2 - 1).abs() > epsilon ||
        (z.length2 - 1).abs() > epsilon ||
        x.dot(y).abs() > epsilon ||
        x.dot(z).abs() > epsilon ||
        y.dot(z).abs() > epsilon ||
        (x.dot(y.cross(z)) - 1).abs() > 5 * epsilon) {
      throw const FormatException(
        'Camera pose rotation must be orthonormal with determinant +1.',
      );
    }
  }
}

class AlignedDepthFrame {
  const AlignedDepthFrame({
    required this.values,
    required this.confidence,
  });

  final Float32List values;
  final Uint8List confidence;
}

/// Registers depth to RGB using each stream's calibrated intrinsics and a
/// nearest-surface z-buffer. This is geometric projection, not image resizing.
class DepthAligner {
  const DepthAligner();

  Float32List alignToRgb(DepthFrame depth, CameraIntrinsics rgbIntrinsics) {
    return alignDepthAndConfidence(depth, rgbIntrinsics).values;
  }

  AlignedDepthFrame alignDepthAndConfidence(
    DepthFrame depth,
    CameraIntrinsics rgbIntrinsics,
  ) {
    depth.validate();
    rgbIntrinsics.validate();
    final aligned = Float32List(rgbIntrinsics.width * rgbIntrinsics.height);
    final confidence = Uint8List(rgbIntrinsics.width * rgbIntrinsics.height);

    for (var y = 0; y < depth.height; y++) {
      for (var x = 0; x < depth.width; x++) {
        final sourceIndex = y * depth.width + x;
        final meters = depth.valuesMeters[sourceIndex];
        final sourceConfidence = depth.confidence[sourceIndex];
        if (meters <= 0 || sourceConfidence == 0) continue;

        final cameraX =
            (x - depth.intrinsics.cx) * meters / depth.intrinsics.fx;
        // Camera coordinates are x-right, y-up, z-back; image y points down.
        final cameraY =
            -(y - depth.intrinsics.cy) * meters / depth.intrinsics.fy;
        final rgbX =
            (rgbIntrinsics.fx * cameraX / meters + rgbIntrinsics.cx).round();
        final rgbY =
            (-rgbIntrinsics.fy * cameraY / meters + rgbIntrinsics.cy).round();
        if (rgbX < 0 ||
            rgbX >= rgbIntrinsics.width ||
            rgbY < 0 ||
            rgbY >= rgbIntrinsics.height) {
          continue;
        }

        final targetIndex = rgbY * rgbIntrinsics.width + rgbX;
        final previous = aligned[targetIndex];
        if (previous == 0 || meters < previous) {
          aligned[targetIndex] = meters;
          confidence[targetIndex] = sourceConfidence;
        }
      }
    }

    return AlignedDepthFrame(values: aligned, confidence: confidence);
  }
}

class MaskedPointCloudBuilder {
  const MaskedPointCloudBuilder();

  List<Vector3> build({
    required CapturedFrame frame,
    required Uint8List rgbMask,
    double minimumConfidence = 0.5,
    double maximumDepthMeters = 5,
    int pixelStride = 2,
  }) {
    frame.validate(requireDepth: true);
    final depth = frame.depth!;
    final aligned = const DepthAligner().alignDepthAndConfidence(
      depth,
      frame.rgbIntrinsics,
    );
    final expected = frame.rgbWidth * frame.rgbHeight;
    if (rgbMask.length != expected) {
      throw const FormatException('Segmentation mask must be aligned to RGB dimensions.');
    }
    if (!minimumConfidence.isFinite ||
        minimumConfidence < 0 ||
        minimumConfidence > 1 ||
        !maximumDepthMeters.isFinite ||
        maximumDepthMeters <= 0 ||
        pixelStride < 1) {
      throw const FormatException('Point-cloud filtering parameters are invalid.');
    }

    final pose = Matrix4.fromList(frame.cameraPose);
    final points = <Vector3>[];
    for (var y = 0; y < frame.rgbHeight; y += pixelStride) {
      for (var x = 0; x < frame.rgbWidth; x += pixelStride) {
        final index = y * frame.rgbWidth + x;
        if (rgbMask[index] < 128) continue;
        final meters = aligned.values[index];
        final confidence = aligned.confidence[index] / 255.0;
        if (meters <= 0 ||
            meters > maximumDepthMeters ||
            confidence < minimumConfidence) {
          continue;
        }

        final local = Vector3(
          (x - frame.rgbIntrinsics.cx) * meters / frame.rgbIntrinsics.fx,
          -(y - frame.rgbIntrinsics.cy) * meters / frame.rgbIntrinsics.fy,
          -meters,
        );
        points.add(pose.transform3(local));
      }
    }
    return points;
  }
}
