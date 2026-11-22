enum ReconstructionBackendKind { rgbd, photogrammetry, nerf, slam, video, meshTexturing }
enum ReconstructionAvailability { available, experimental, unsupported }

class ReconstructionCapability {
  const ReconstructionCapability({required this.backend, required this.availability, required this.reason, this.requiresDesktop = false});
  final ReconstructionBackendKind backend;
  final ReconstructionAvailability availability;
  final String reason;
  final bool requiresDesktop;
}

class CameraIntrinsics {
  const CameraIntrinsics({required this.fx, required this.fy, required this.cx, required this.cy, required this.width, required this.height});
  final double fx, fy, cx, cy;
  final int width, height;
  void validate() {
    if (![fx, fy, cx, cy].every((v) => v.isFinite) || fx <= 0 || fy <= 0 || width <= 0 || height <= 0 || cx < 0 || cy < 0 || cx >= width || cy >= height) {
      throw const FormatException('Invalid camera intrinsics.');
    }
  }
}

class ReconstructionFrame {
  const ReconstructionFrame({required this.timestampNs, required this.rgbTimestampNs, required this.cameraPose, required this.intrinsics, required this.imageWidth, required this.imageHeight, this.depthMeters, this.depthConfidence});
  final int timestampNs, rgbTimestampNs;
  /// Column-major 4x4 camera-to-world transform in metres.
  final List<double> cameraPose;
  final CameraIntrinsics intrinsics;
  final int imageWidth, imageHeight;
  final List<double>? depthMeters;
  final List<int>? depthConfidence;
  void validate() {
    intrinsics.validate();
    if (timestampNs <= 0 || rgbTimestampNs <= 0 || imageWidth != intrinsics.width || imageHeight != intrinsics.height || cameraPose.length != 16 || cameraPose.any((v) => !v.isFinite)) {
      throw const FormatException('Invalid reconstruction frame metadata.');
    }
    if (depthMeters != null && (depthMeters!.isEmpty || depthMeters!.any((v) => !v.isFinite || v < 0))) {
      throw const FormatException('Invalid depth values.');
    }
    if (depthConfidence != null && (depthMeters == null || depthConfidence!.length != depthMeters!.length || depthConfidence!.any((v) => v < 0 || v > 255))) {
      throw const FormatException('Depth confidence does not match depth data.');
    }
  }
}

class ReconstructionSequence {
  ReconstructionSequence(Iterable<ReconstructionFrame> frames) : frames = List.unmodifiable(frames);
  final List<ReconstructionFrame> frames;
  void validate({int minimumFrames = 1}) {
    if (frames.length < minimumFrames) throw FormatException('At least $minimumFrames frames are required.');
    var previous = 0;
    for (final frame in frames) {
      frame.validate();
      if (frame.timestampNs <= previous) throw const FormatException('Frame timestamps must be strictly increasing.');
      previous = frame.timestampNs;
    }
  }
}

class ReconstructionArtifact {
  const ReconstructionArtifact({required this.uri, required this.format, required this.vertexCount, required this.triangleCount, required this.hasUv, required this.hasTexture, required this.hasMetricScale});
  final Uri uri;
  final String format;
  final int vertexCount, triangleCount;
  final bool hasUv, hasTexture, hasMetricScale;
  void validate() {
    if (!uri.isAbsolute || format.trim().isEmpty || vertexCount < 0 || triangleCount < 0 || (hasTexture && !hasUv)) {
      throw const FormatException('Invalid reconstruction artifact metadata.');
    }
  }
}

/// Backends must report unsupported operations explicitly; placeholder meshes are forbidden.
abstract interface class ReconstructionBackend {
  ReconstructionCapability get capability;
  Future<ReconstructionArtifact> reconstruct(ReconstructionSequence sequence);
}

class UnsupportedReconstructionBackend implements ReconstructionBackend {
  const UnsupportedReconstructionBackend(this.capability);
  @override
  final ReconstructionCapability capability;
  @override
  Future<ReconstructionArtifact> reconstruct(ReconstructionSequence sequence) async {
    sequence.validate();
    throw UnsupportedError(capability.reason);
  }
}
