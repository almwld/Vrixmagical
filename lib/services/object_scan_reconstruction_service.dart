import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:vector_math/vector_math_64.dart';

import '../domain/captured_frame.dart';
import 'object_scan_store.dart';
import 'voxel_mesh_reconstruction.dart';

class ObjectScanReconstructionResult {
  const ObjectScanReconstructionResult({
    required this.mesh,
    required this.glbFile,
    required this.inputViewCount,
    required this.inputPointCount,
    required this.voxelPointCount,
  });

  final ReconstructedVoxelMesh mesh;
  final File glbFile;
  final int inputViewCount;
  final int inputPointCount;
  final int voxelPointCount;
}

/// Loads the durable RGB-D scan, rebuilds a bounded point cloud in world
/// coordinates, creates a conservative voxel surface and exports GLB.
class ObjectScanReconstructionService {
  const ObjectScanReconstructionService();

  Future<ObjectScanReconstructionResult> reconstruct(
    ObjectScanSession session, {
    double voxelSizeMeters = 0.015,
    double maximumDepthMeters = 4.0,
    int pixelStride = 3,
  }) async {
    if (!session.isComplete) {
      throw StateError('Finish the capture session before reconstruction.');
    }
    final manifestFile = File(session.manifestPath);
    final manifest = jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
    final views = manifest['views'] as List<dynamic>? ?? const [];
    if (views.length < 3) throw StateError('At least three saved views are required.');
    final allPoints = <Vector3>[];
    var depthViews = 0;

    for (final raw in views) {
      final view = Map<String, dynamic>.from(raw as Map);
      final depthMap = view['depthMap'];
      if (depthMap == null) continue;
      final depthInfo = Map<String, dynamic>.from(depthMap as Map);
      final width = (depthInfo['width'] as num).toInt();
      final height = (depthInfo['height'] as num).toInt();
      if (width <= 0 || height <= 0 || width * height > 16000000) {
        throw const FormatException('Stored depth dimensions exceed reconstruction limits.');
      }
      final depthFile = File('${session.directory.path}/${depthInfo['file']}');
      final confidenceFile = File('${session.directory.path}/${depthInfo['confidenceFile']}');
      final bytes = await depthFile.readAsBytes();
      if (bytes.length != width * height * 4) {
        throw const FormatException('Stored depth buffer is truncated.');
      }
      final depthData = ByteData.sublistView(bytes);
      final values = Float32List(width * height);
      for (var i = 0; i < values.length; i++) {
        values[i] = depthData.getFloat32(i * 4, Endian.little);
      }
      var confidence = await confidenceFile.readAsBytes();
      final confidenceAvailable = depthInfo['confidenceAvailable'] as bool? ?? false;
      if (confidence.length != width * height) {
        throw const FormatException('Stored confidence buffer is truncated.');
      }
      // AUTOMATIC depth may not expose a confidence plane. Use a neutral
      // acceptance mask for geometry filtering, while retaining provenance.
      if (!confidenceAvailable) confidence = Uint8List(width * height)..fillRange(0, width * height, 255);

      final rgbIntrinsics = _intrinsics(view['rgbIntrinsics']);
      final depthIntrinsics = _intrinsics(depthInfo['intrinsics']);
      final poseValues = (view['cameraPose'] as List<dynamic>?)
          ?.map((v) => (v as num).toDouble()).toList(growable: false);
      if (poseValues == null || poseValues.length != 16) {
        throw const FormatException('A synchronized camera pose is missing from a depth view.');
      }
      final frameTimestamp = (view['frameTimestampNs'] as num?)?.toInt() ?? 0;
      final rgbTimestamp = (view['rgbTimestampNs'] as num?)?.toInt() ?? 0;
      final imageFile = File('${session.directory.path}/${view['image']}');
      final rgbBytes = await imageFile.readAsBytes();
      final support = depthInfo['isRaw'] == true
          ? VrixDepthSupport.rawOnly
          : VrixDepthSupport.automatic;
      final frame = CapturedFrame(
        rgbBytes: rgbBytes,
        frameTimestampNs: frameTimestamp,
        rgbTimestampNs: rgbTimestamp,
        rgbIntrinsics: rgbIntrinsics,
        cameraPose: Float64List.fromList(poseValues),
        trackingState: VrixTrackingState.tracking,
        depthSupport: support,
        depth: DepthFrame(
          valuesMeters: values,
          confidence: Uint8List.fromList(confidence),
          width: width,
          height: height,
          frameTimestampNs: frameTimestamp,
          imageTimestampNs: (depthInfo['imageTimestampNs'] as num).toInt(),
          intrinsics: depthIntrinsics,
          isRaw: depthInfo['isRaw'] as bool? ?? false,
          isReprojected: depthInfo['isReprojected'] as bool? ?? false,
          confidenceAvailable: confidenceAvailable,
        ),
      );

      final maskFile = File('${session.directory.path}/${view['mask']}');
      final maskBytes = await maskFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(maskBytes);
      final imageFrame = await codec.getNextFrame();
      final maskImage = imageFrame.image;
      try {
        final rgba = await maskImage.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (rgba == null) throw StateError('Unable to decode a saved segmentation mask.');
        final alpha = Uint8List(maskImage.width * maskImage.height);
        final data = rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes);
        for (var i = 0; i < alpha.length; i++) {
          alpha[i] = data[i * 4 + 3];
        }
        final alignedMask = const SegmentationMaskAligner().alignNearestNeighbor(
          mask: alpha,
          maskWidth: maskImage.width,
          maskHeight: maskImage.height,
          rgbWidth: rgbIntrinsics.width,
          rgbHeight: rgbIntrinsics.height,
        );
        allPoints.addAll(const MaskedPointCloudBuilder().build(
          frame: frame,
          rgbMask: alignedMask,
          minimumConfidence: confidenceAvailable ? 0.35 : 0,
          maximumDepthMeters: maximumDepthMeters,
          pixelStride: pixelStride,
        ));
      } finally {
        maskImage.dispose();
        codec.dispose();
      }
      depthViews++;
    }

    if (depthViews < 3) {
      throw StateError('At least three views with synchronized depth are required; found $depthViews.');
    }
    if (allPoints.length < 8) {
      throw StateError('Too few valid masked depth points. Retake views with better lighting and depth coverage.');
    }
    final fused = const PointCloudVoxelFusion().downsample(
      allPoints,
      voxelSizeMeters: voxelSizeMeters,
      maximumOutputPoints: 200000,
    );
    final mesh = const VoxelMeshReconstructor().reconstruct(
      fused,
      voxelSizeMeters: voxelSizeMeters,
      maximumOccupiedVoxels: 10000,
      maximumSurfaceFaces: 25000,
    );
    final glb = File('${session.directory.path}/reconstruction.glb');
    await mesh.exportGlb(glb);

    manifest['reconstruction'] = {
      'status': 'voxel_surface_preview',
      'algorithm': 'world-space-voxel-occupancy-boundary',
      'isPhotogrammetry': false,
      'isProductionSurface': false,
      'output': 'reconstruction.glb',
      'collider': 'reconstruction.glb',
      'inputViews': views.length,
      'depthViews': depthViews,
      'inputPoints': allPoints.length,
      'fusedPoints': fused.length,
      'vertices': mesh.vertices.length,
      'triangles': mesh.triangleCount,
      'voxelSizeMeters': voxelSizeMeters,
      'note': 'Conservative voxel surface and static collider preview. Validate scan coverage and geometry on-device before production use.',
    };
    final temporary = File('${session.manifestPath}.tmp');
    await temporary.writeAsString(jsonEncode(manifest), flush: true);
    await temporary.rename(session.manifestPath);
    return ObjectScanReconstructionResult(
      mesh: mesh,
      glbFile: glb,
      inputViewCount: views.length,
      inputPointCount: allPoints.length,
      voxelPointCount: fused.length,
    );
  }

  CameraIntrinsics _intrinsics(Object? raw) {
    final value = Map<String, dynamic>.from(raw as Map);
    return CameraIntrinsics(
      fx: (value['fx'] as num).toDouble(),
      fy: (value['fy'] as num).toDouble(),
      cx: (value['cx'] as num).toDouble(),
      cy: (value['cy'] as num).toDouble(),
      width: (value['width'] as num).toInt(),
      height: (value['height'] as num).toInt(),
    );
  }
}
