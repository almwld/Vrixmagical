import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_reality/managers/ar_session_manager.dart';
import 'package:mediapipe_vision/mediapipe_vision.dart';
import 'package:vector_math/vector_math_64.dart';

import '../domain/captured_frame.dart';
import '../features/hand/hand_gesture_math.dart';

/// A hand observation measured from the same RGB-D/pose sample acquired by
/// the active ARCore session. World points are omitted when depth is absent or
/// invalid; normalized landmarks remain available for screen-space gestures.
class ArTrackedHand {
  const ArTrackedHand({
    required this.handedness,
    required this.landmarks,
    required this.pinchRatio,
    required this.isPinching,
    required this.pinchEvent,
    required this.worldLandmarks,
  });

  final String handedness;
  final List<Offset> landmarks;
  final double? pinchRatio;
  final bool isPinching;
  final PinchEvent? pinchEvent;
  final Map<int, Vector3> worldLandmarks;

  Vector3? get thumbTipWorld => worldLandmarks[4];
  Vector3? get indexTipWorld => worldLandmarks[8];
}

/// Output from one synchronized ARCore capture and MediaPipe inference pass.
class ArHandObservation {
  const ArHandObservation({
    required this.frameTimestampNs,
    required this.rgbTimestampNs,
    required this.cameraPose,
    required this.hands,
    required this.depthAvailable,
  });

  final int frameTimestampNs;
  final int rgbTimestampNs;
  final Float64List cameraPose;
  final List<ArTrackedHand> hands;
  final bool depthAvailable;
}

/// Converts a normalized image landmark into AR world coordinates by sampling
/// registered depth and applying the frame's world-from-camera pose.
class ArDepthProjector {
  const ArDepthProjector();

  Vector3? project({
    required Offset normalizedPoint,
    required CameraIntrinsics rgbIntrinsics,
    required DepthFrame? depth,
    required Float64List cameraPose,
    int sampleRadius = 2,
  }) {
    if (depth == null ||
        cameraPose.length != 16 ||
        cameraPose.any((value) => !value.isFinite) ||
        !normalizedPoint.dx.isFinite ||
        !normalizedPoint.dy.isFinite ||
        normalizedPoint.dx < 0 ||
        normalizedPoint.dx > 1 ||
        normalizedPoint.dy < 0 ||
        normalizedPoint.dy > 1 ||
        sampleRadius < 0) {
      return null;
    }

    try {
      depth.validate();
      rgbIntrinsics.validate();
      final aligned = const DepthAligner().alignDepthAndConfidence(
        depth,
        rgbIntrinsics,
      );
      final centerX = (normalizedPoint.dx * (rgbIntrinsics.width - 1)).round();
      final centerY = (normalizedPoint.dy * (rgbIntrinsics.height - 1)).round();
      final samples = <double>[];
      for (var y = centerY - sampleRadius; y <= centerY + sampleRadius; y++) {
        if (y < 0 || y >= rgbIntrinsics.height) continue;
        for (var x = centerX - sampleRadius; x <= centerX + sampleRadius; x++) {
          if (x < 0 || x >= rgbIntrinsics.width) continue;
          final index = y * rgbIntrinsics.width + x;
          final meters = aligned.values[index];
          final confidence = aligned.confidence[index];
          if (meters.isFinite && meters > 0 &&
              (!depth.confidenceAvailable || confidence > 0)) {
            samples.add(meters);
          }
        }
      }
      if (samples.isEmpty) return null;
      samples.sort();
      final zMeters = samples[samples.length ~/ 2];
      final cameraX =
          (centerX - rgbIntrinsics.cx) * zMeters / rgbIntrinsics.fx;
      final cameraY =
          -(centerY - rgbIntrinsics.cy) * zMeters / rgbIntrinsics.fy;
      final worldPoint = Vector3(cameraX, cameraY, -zMeters);
      Matrix4.fromList(cameraPose.toList()).transform3(worldPoint);
      if (!worldPoint.x.isFinite ||
          !worldPoint.y.isFinite ||
          !worldPoint.z.isFinite) {
        return null;
      }
      return worldPoint;
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }
}

/// Runs MediaPipe on RGB frames captured by the existing ARCore session.
///
/// It deliberately does not create a CameraController: ARCore remains the
/// sole owner of the camera. Capture is serialized and rate-limited so image
/// conversion or inference can never queue an unbounded backlog.
class ArSessionHandPerception {
  ArSessionHandPerception({
    this.captureInterval = const Duration(milliseconds: 180),
    this.onObservation,
    this.onError,
  }) {
    if (captureInterval < const Duration(milliseconds: 80)) {
      throw ArgumentError('AR hand capture interval must be at least 80 ms.');
    }
  }

  final Duration captureInterval;
  final ValueChanged<ArHandObservation>? onObservation;
  final ValueChanged<Object>? onError;

  final Stopwatch _clock = Stopwatch();
  final Map<String, PinchGesture> _pinchGestures = <String, PinchGesture>{};
  ARSessionManager? _session;
  HandLandmarker? _landmarker;
  Timer? _timer;
  Future<void>? _inFlight;
  bool _running = false;
  int _lastTimestampMilliseconds = -1;

  bool get isRunning => _running;

  Future<void> start(ARSessionManager session) async {
    await stop();
    _session = session;
    try {
      final landmarker = await HandLandmarker.create(
        HandLandmarkerOptions(
          model: VisionModels.handLandmarker,
          numHands: 2,
          runningMode: RunningMode.video,
        ),
      );
      _landmarker = landmarker;
      _clock
        ..reset()
        ..start();
      _lastTimestampMilliseconds = -1;
      _pinchGestures.clear();
      _running = true;
      _timer = Timer.periodic(captureInterval, (_) => _scheduleCapture());
    } catch (error) {
      _session = null;
      final landmarker = _landmarker;
      _landmarker = null;
      await landmarker?.dispose();
      rethrow;
    }
  }

  void _scheduleCapture() {
    if (!_running || _inFlight != null) return;
    final task = _captureOneFrame();
    _inFlight = task;
    unawaited(task.whenComplete(() {
      if (identical(_inFlight, task)) _inFlight = null;
    }));
  }

  Future<void> _captureOneFrame() async {
    final session = _session;
    final landmarker = _landmarker;
    if (!_running || session == null || landmarker == null) return;

    try {
      final payload = await session.captureSynchronizedFrame();
      if (!_running) return;
      final rgbBytes = payload['rgbBytes'];
      final frameTimestampNs = payload['frameTimestampNs'];
      final rgbTimestampNs = payload['rgbTimestampNs'];
      final poseValue = payload['cameraPose'];
      final rgbIntrinsicsValue = payload['rgbIntrinsics'];
      if (rgbBytes is! Uint8List ||
          frameTimestampNs is! num ||
          rgbTimestampNs is! num ||
          poseValue is! List ||
          rgbIntrinsicsValue is! Map) {
        throw const FormatException('ARCore returned an invalid synchronized RGB-D frame.');
      }

      final pose = Float64List.fromList(
        poseValue.map((value) => (value as num).toDouble()).toList(),
      );
      final rgbIntrinsics = _readIntrinsics(
        Map<String, Object?>.from(rgbIntrinsicsValue),
      );
      final decoded = await _decodeJpeg(rgbBytes);
      try {
        if (decoded.width != rgbIntrinsics.width ||
            decoded.height != rgbIntrinsics.height) {
          throw const FormatException(
            'Decoded AR image dimensions do not match calibrated intrinsics.',
          );
        }
        final frameTimestampMilliseconds =
            (frameTimestampNs.toInt() ~/ 1000000);
        final timestamp = frameTimestampMilliseconds > _lastTimestampMilliseconds
            ? frameTimestampMilliseconds
            : _lastTimestampMilliseconds + 1;
        _lastTimestampMilliseconds = timestamp;

        final result = await landmarker.detectForVideo(
          VisionImage.fromPixels(
            pixels: decoded.rgba,
            width: decoded.width,
            height: decoded.height,
            format: VisionPixelFormat.rgba,
          ),
          timestampMilliseconds: timestamp,
        );
        if (!_running) return;

        final depth = _readDepth(
          payload['depth'],
          frameTimestampNs.toInt(),
        );
        final hands = <ArTrackedHand>[];
        for (var handIndex = 0;
            handIndex < result.handLandmarks.length;
            handIndex++) {
          final rawLandmarks = result.handLandmarks[handIndex];
          final landmarks = rawLandmarks
              .map((point) => Offset(point.x, point.y))
              .toList(growable: false);
          final handedness = handIndex < result.handedness.length &&
                  result.handedness[handIndex].isNotEmpty
              ? result.handedness[handIndex].first.categoryName
              : 'Unknown';
          final gesture = _pinchGestures.putIfAbsent(
            handedness,
            PinchGesture.new,
          );
          final ratio = HandGestureMath.pinchRatio(
            landmarks,
            imageAspectRatio:
                rgbIntrinsics.width / rgbIntrinsics.height,
          );
          final event = gesture.update(
            ratio,
            timestamp / 1000.0,
          );
          final world = <int, Vector3>{};
          for (final landmarkIndex in const [0, 4, 8, 9, 12, 16, 20]) {
            if (landmarkIndex >= landmarks.length) continue;
            final point = const ArDepthProjector().project(
              normalizedPoint: landmarks[landmarkIndex],
              rgbIntrinsics: rgbIntrinsics,
              depth: depth,
              cameraPose: pose,
            );
            if (point != null) world[landmarkIndex] = point;
          }
          hands.add(
            ArTrackedHand(
              handedness: handedness,
              landmarks: landmarks,
              pinchRatio: ratio,
              isPinching: gesture.isPinched,
              pinchEvent: event,
              worldLandmarks: Map.unmodifiable(world),
            ),
          );
        }

        onObservation?.call(
          ArHandObservation(
            frameTimestampNs: frameTimestampNs.toInt(),
            rgbTimestampNs: rgbTimestampNs.toInt(),
            cameraPose: pose,
            hands: List.unmodifiable(hands),
            depthAvailable: depth != null,
          ),
        );
      } finally {
        decoded.dispose();
      }
    } catch (error) {
      if (_running) onError?.call(error);
    }
  }

  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
    final pending = _inFlight;
    if (pending != null) await pending;
    final landmarker = _landmarker;
    _landmarker = null;
    _session = null;
    _pinchGestures.clear();
    _clock.stop();
    await landmarker?.dispose();
  }

  Future<void> dispose() => stop();

  static CameraIntrinsics _readIntrinsics(Map<String, Object?> value) {
    num number(String key) {
      final item = value[key];
      if (item is! num) throw FormatException('Missing camera intrinsic: $key');
      return item;
    }

    return CameraIntrinsics(
      fx: number('fx').toDouble(),
      fy: number('fy').toDouble(),
      cx: number('cx').toDouble(),
      cy: number('cy').toDouble(),
      width: number('width').toInt(),
      height: number('height').toInt(),
    );
  }

  static DepthFrame? _readDepth(Object? value, int frameTimestampNs) {
    if (value is! Map) return null;
    final map = Map<String, Object?>.from(value);
    final width = map['width'];
    final height = map['height'];
    final imageTimestampNs = map['imageTimestampNs'];
    final valuesBytes = map['valuesLittleEndian'];
    final confidenceValue = map['confidence'];
    final intrinsicsValue = map['intrinsics'];
    if (width is! num ||
        height is! num ||
        imageTimestampNs is! num ||
        valuesBytes is! Uint8List ||
        intrinsicsValue is! Map) {
      return null;
    }
    final count = width.toInt() * height.toInt();
    if (count <= 0 || valuesBytes.lengthInBytes != count * 4) return null;
    final data = ByteData.sublistView(valuesBytes);
    final values = Float32List(count);
    for (var i = 0; i < count; i++) {
      values[i] = data.getFloat32(i * 4, Endian.little);
    }
    final confidence = confidenceValue is Uint8List &&
            confidenceValue.length == count
        ? confidenceValue
        : Uint8List(count)..fillRange(0, count, 255);
    return DepthFrame(
      valuesMeters: values,
      confidence: confidence,
      width: width.toInt(),
      height: height.toInt(),
      frameTimestampNs: frameTimestampNs,
      imageTimestampNs: imageTimestampNs.toInt(),
      intrinsics: _readIntrinsics(
        Map<String, Object?>.from(intrinsicsValue),
      ),
      isRaw: map['isRaw'] == true,
      isReprojected: map['isReprojected'] == true,
      confidenceAvailable: map['confidenceAvailable'] == true,
    );
  }

  static Future<_DecodedRgba> _decodeJpeg(Uint8List jpeg) async {
    final codec = await ui.instantiateImageCodec(jpeg);
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data == null) throw const FormatException('AR JPEG could not be decoded to RGBA.');
        return _DecodedRgba(
          rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          width: image.width,
          height: image.height,
          image: image,
        );
      } catch (_) {
        image.dispose();
        rethrow;
      }
    } finally {
      codec.dispose();
    }
  }
}

class _DecodedRgba {
  const _DecodedRgba({
    required this.rgba,
    required this.width,
    required this.height,
    required this.image,
  });

  final Uint8List rgba;
  final int width;
  final int height;
  final ui.Image image;

  void dispose() => image.dispose();
}
