import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mediapipe_vision/mediapipe_vision.dart';

import '../../app/app_theme.dart';
import 'hand_gesture_math.dart';

class HandMirrorScreen extends StatefulWidget {
  const HandMirrorScreen({super.key});
  @override
  State<HandMirrorScreen> createState() => _HandMirrorScreenState();
}

class _HandMirrorScreenState extends State<HandMirrorScreen> {
  CameraController? _camera;
  HandLandmarker? _landmarker;
  StreamSubscription<HandLandmarkerResult>? _results;
  final Stopwatch _clock = Stopwatch()..start();
  int _lastTimestamp = -1;
  int _frameNumber = 0;
  bool _starting = true;
  bool _shuttingDown = false;
  bool _frameBusy = false;
  bool _pinching = false;
  Offset? _indexPosition;
  Offset? _assetPosition;
  String _status = 'جارٍ تجهيز تتبع اليد…';
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('لم يتم العثور على كاميرا.');
      final selected = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final camera = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      _camera = camera;
      await camera.initialize();

      final landmarker = await HandLandmarker.create(
        HandLandmarkerOptions(
          model: VisionModels.handLandmarker,
          numHands: 2,
          runningMode: RunningMode.liveStream,
        ),
      );
      _landmarker = landmarker;
      _results = landmarker.results.listen(
        _onHandResult,
        onError: (Object error) {
          if (mounted) setState(() => _status = 'تعذّر تتبع اليد: ' + error.toString());
        },
      );
      await camera.startImageStream(_onCameraFrame);
      if (mounted) {
        setState(() {
          _starting = false;
          _status = 'أظهر يدك أمام الكاميرا ثم قرّب الإبهام والسبابة.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _starting = false;
          _error = error.toString();
          _status = 'تعذّر تشغيل الكاميرا أو نموذج MediaPipe.';
        });
      }
    }
  }

  void _onCameraFrame(CameraImage image) {
    final landmarker = _landmarker;
    if (_shuttingDown || landmarker == null || _frameBusy) return;
    _frameNumber++;
    if (_frameNumber % 3 != 0) return;

    _frameBusy = true;
    final now = _clock.elapsedMilliseconds;
    _lastTimestamp = now > _lastTimestamp ? now : _lastTimestamp + 1;
    final rotation = _camera?.description.sensorOrientation ?? 0;
    try {
      landmarker.detectAsync(
        VisionImage.deferred(
          () => VisionImage.fromPixels(
            pixels: _toRgba(image),
            width: image.width,
            height: image.height,
            format: VisionPixelFormat.rgba,
          ),
        ),
        timestampMilliseconds: _lastTimestamp,
        rotationDegrees: rotation,
      );
    } catch (error) {
      _frameBusy = false;
      if (mounted) {
        setState(() => _status = 'تعذّرت معالجة إطار الكاميرا: $error');
      }
    }
  }

  void _onHandResult(HandLandmarkerResult result) {
    _frameBusy = false;
    if (!mounted || _shuttingDown) return;
    if (result.handLandmarks.isEmpty) {
      setState(() {
        _pinching = false;
        _indexPosition = null;
        _status = 'لم يتم رصد يد. قرّب يدك من مجال الكاميرا.';
      });
      return;
    }
    final landmarks = result.handLandmarks.first;
    if (landmarks.length <= 8) return;
    final thumb = Offset(landmarks[4].x, landmarks[4].y);
    final index = Offset(landmarks[8].x, landmarks[8].y);
    final pinch = HandGestureMath.isPinching(thumb, index);
    final point = Offset(1 - index.dx, index.dy);

    setState(() {
      _pinching = pinch;
      _indexPosition = point;
      if (pinch) _assetPosition = point;
      _status = pinch
          ? 'تم الإمساك بالأصل الرقمي — حرّك يدك.'
          : 'تم رصد اليد. اقرص بالإبهام والسبابة للإمساك.';
    });
  }

  Uint8List _toRgba(CameraImage image) {
    if (image.planes.length == 1) {
      final plane = image.planes.first;
      final source = plane.bytes;
      final rgba = Uint8List(image.width * image.height * 4);
      final pixelStride = plane.bytesPerPixel ?? 4;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final sourceIndex = y * plane.bytesPerRow + x * pixelStride;
          final targetIndex = (y * image.width + x) * 4;
          rgba[targetIndex] = source[sourceIndex];
          rgba[targetIndex + 1] = source[sourceIndex + 1];
          rgba[targetIndex + 2] = source[sourceIndex + 2];
          rgba[targetIndex + 3] = 255;
        }
      }
      return rgba;
    }
    if (image.planes.length < 3) {
      throw const FormatException('تنسيق صورة الكاميرا غير مدعوم.');
    }
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final rgba = Uint8List(image.width * image.height * 4);
    for (var y = 0; y < image.height; y++) {
      final yRow = yPlane.bytesPerRow * y;
      final uvRow = uPlane.bytesPerRow * (y >> 1);
      final vRow = vPlane.bytesPerRow * (y >> 1);
      for (var x = 0; x < image.width; x++) {
        final uvColumn = x >> 1;
        final yValue = yPlane.bytes[yRow + x];
        final uValue = uPlane.bytes[uvRow + uvColumn * (uPlane.bytesPerPixel ?? 1)];
        final vValue = vPlane.bytes[vRow + uvColumn * (vPlane.bytesPerPixel ?? 1)];
        final yAdjusted = math.max(0, yValue - 16);
        final u = uValue - 128;
        final v = vValue - 128;
        final r = (1.164 * yAdjusted + 1.596 * v).round();
        final g = (1.164 * yAdjusted - 0.392 * u - 0.813 * v).round();
        final b = (1.164 * yAdjusted + 2.017 * u).round();
        final offset = (y * image.width + x) * 4;
        rgba[offset] = r.clamp(0, 255).toInt();
        rgba[offset + 1] = g.clamp(0, 255).toInt();
        rgba[offset + 2] = b.clamp(0, 255).toInt();
        rgba[offset + 3] = 255;
      }
    }
    return rgba;
  }

  Future<void> _shutdown() async {
    if (_shuttingDown) return;
    _shuttingDown = true;
    final camera = _camera;
    final results = _results;
    final landmarker = _landmarker;
    _camera = null;
    _results = null;
    _landmarker = null;

    if (camera != null) {
      try {
        if (camera.value.isStreamingImages) {
          await camera.stopImageStream();
        }
      } catch (_) {
        // Continue releasing the remaining camera and inference resources.
      }
    }
    await results?.cancel();
    await landmarker?.dispose();
    await camera?.dispose();
  }

  @override
  void dispose() {
    unawaited(_shutdown());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('مرآة اليد الرقمية'),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: (_error == null ? AppColors.success : Colors.redAccent)
                      .withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.circle,
                      size: 6,
                      color: _error == null ? AppColors.success : Colors.redAccent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _error == null ? 'HAND TRACKING' : 'OFFLINE',
                      style: TextStyle(
                        color: _error == null ? AppColors.success : Colors.redAccent,
                        fontSize: 8,
                        letterSpacing: .8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (camera != null && camera.value.isInitialized)
            CameraPreview(camera)
          else
            const ColoredBox(
              color: AppColors.background,
              child: Center(
                child: Icon(
                  Icons.back_hand_outlined,
                  size: 54,
                  color: AppColors.muted,
                ),
              ),
            ),
          if (_indexPosition != null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _HandPointPainter(_indexPosition!),
                ),
              ),
            ),
          if (_assetPosition != null)
            Positioned(
              left: (_assetPosition!.dx * size.width - 38)
                  .clamp(8.0, size.width - 84),
              top: (_assetPosition!.dy * size.height - 110)
                  .clamp(90.0, size.height - 190),
              child: IgnorePointer(
                child: _DigitalAsset(isHeld: _pinching),
              ),
            ),
          if (_starting)
            const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          Positioned(
            left: 16,
            right: 16,
            top: 16,
            child: _TrackingMetric(
              active: _indexPosition != null,
              pinching: _pinching,
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 16,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xEE101A28),
                  borderRadius: BorderRadius.circular(21),
                  border: Border.all(color: AppColors.primary.withValues(alpha: .3)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x55000000),
                      blurRadius: 24,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.touch_app_rounded,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _status,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 11,
                          height: 1.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DigitalAsset extends StatelessWidget {
  const _DigitalAsset({required this.isHeld});
  final bool isHeld;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 100),
    width: 76, height: 76,
    decoration: BoxDecoration(
      color: const Color(0xDD102B39),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: isHeld ? const Color(0xFF6BFFE9) : const Color(0xFF45BFB4), width: isHeld ? 3 : 1.5),
      boxShadow: [BoxShadow(color: const Color(0xFF42E8D5).withValues(alpha: isHeld ? .35 : .12), blurRadius: isHeld ? 24 : 10)],
    ),
    child: Icon(Icons.local_cafe_rounded, size: 39, color: isHeld ? const Color(0xFF8FFFF0) : const Color(0xFF55E3D4)),
  );
}

class _HandPointPainter extends CustomPainter {
  const _HandPointPainter(this.point);
  final Offset point;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(point.dx * size.width, point.dy * size.height);
    final paint = Paint()..color = const Color(0xFF64FFE8)..style = PaintingStyle.stroke..strokeWidth = 2;
    canvas.drawCircle(center, 13, paint);
    canvas.drawCircle(center, 3, Paint()..color = const Color(0xFF64FFE8));
  }

  @override
  bool shouldRepaint(covariant _HandPointPainter oldDelegate) => oldDelegate.point != point;
}
