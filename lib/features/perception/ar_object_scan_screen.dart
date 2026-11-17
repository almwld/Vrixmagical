import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_reality/ar_flutter_plugin.dart';
import 'package:flutter_reality/datatypes/config_planedetection.dart';
import 'package:flutter_reality/managers/ar_anchor_manager.dart';
import 'package:flutter_reality/managers/ar_location_manager.dart';
import 'package:flutter_reality/managers/ar_object_manager.dart';
import 'package:flutter_reality/managers/ar_session_manager.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mediapipe_vision/mediapipe_vision.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/app_theme.dart';
import '../../domain/captured_frame.dart';
import '../../services/object_scan_store.dart';
import '../../services/object_scan_reconstruction_service.dart';
import '../../services/physics_scene_service.dart';

/// Captures RGB, calibrated ARCore world pose and a user-refined mask from
/// the same AR session. ARCore remains the sole camera/session owner.
class ArObjectScanScreen extends StatefulWidget {
  const ArObjectScanScreen({super.key});

  @override
  State<ArObjectScanScreen> createState() => _ArObjectScanScreenState();
}

class _ArObjectScanScreenState extends State<ArObjectScanScreen> {
  ARSessionManager? _session;
  InteractiveSegmenter? _segmenter;
  ObjectScanStore? _store;
  String? _photoPath;
  ui.Image? _maskImage;
  int _imageWidth = 1;
  int _imageHeight = 1;
  int _maskWidth = 1;
  int _maskHeight = 1;
  List<double>? _cameraPose;
  CapturedFrame? _capturedFrame;
  double? _promptX;
  double? _promptY;
  final List<Stroke> _strokes = [];
  bool _busy = false;
  bool _saved = false;
  bool _completed = false;
  PhysicsSceneService? _physicsScene;
  ObjectScanReconstructionResult? _reconstruction;
  String _status = 'حرّك الهاتف ببطء حتى يستقر تتبع ARCore، ثم التقط المنظور الأول.';
  String? _error;

  Rect _imageRect(Size viewport) {
    final fitted = applyBoxFit(
      BoxFit.contain,
      Size(_imageWidth.toDouble(), _imageHeight.toDouble()),
      viewport,
    );
    return Alignment.center.inscribe(fitted.destination, Offset.zero & viewport);
  }

  void _onArCreated(
    ARSessionManager session,
    ARObjectManager objects,
    ARAnchorManager anchors,
    ARLocationManager locations,
  ) {
    _session = session;
    session.onError = (message) {
      if (mounted) setState(() => _error = message);
    };
    session.onInitialize(
      showAnimatedGuide: false,
      showPlanes: false,
      showFeaturePoints: false,
      handleTaps: false,
      handlePans: false,
      handleRotation: false,
    ).then((_) {
      if (mounted) setState(() => _status =
          'تتبّع ARCore جاهز. تحرّك حول الجسم مع إبقائه داخل مجال الرؤية.');
    }).catchError((Object error) {
      if (mounted) setState(() => _error = 'تعذّر تهيئة جلسة AR: $error');
    });
  }

  Future<void> _captureView() async {
    final session = _session;
    if (_busy || _completed || session == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = 'جارٍ انتظار إطار RGB-D متزامن من جلسة ARCore…';
    });
    try {
      // Native bridge samples CPU RGB, pose, intrinsics and depth inside the
      // same ARCore Frame callback. PixelCopy and a second session.update()
      // are deliberately not used for reconstruction data.
      final payload = await session.captureSynchronizedFrame();
      Map<String, dynamic> asMap(Object? value) =>
          Map<String, dynamic>.from(value as Map);
      CameraIntrinsics readIntrinsics(Object? value) {
        final map = asMap(value);
        return CameraIntrinsics(
          fx: (map['fx'] as num).toDouble(),
          fy: (map['fy'] as num).toDouble(),
          cx: (map['cx'] as num).toDouble(),
          cy: (map['cy'] as num).toDouble(),
          width: (map['width'] as num).toInt(),
          height: (map['height'] as num).toInt(),
        );
      }

      final rgbBytes = payload['rgbBytes'] as Uint8List;
      final pose = Float64List.fromList(
        (payload['cameraPose'] as List)
            .map((value) => (value as num).toDouble())
            .toList(growable: false),
      );
      final depthPayload = payload['depth'] == null
          ? null
          : asMap(payload['depth']);
      DepthFrame? depth;
      if (depthPayload != null) {
        final width = (depthPayload['width'] as num).toInt();
        final height = (depthPayload['height'] as num).toInt();
        final depthBytes = depthPayload['valuesLittleEndian'] as Uint8List;
        if (depthBytes.length != width * height * 4) {
          throw const FormatException('Native depth buffer length does not match its dimensions.');
        }
        final data = ByteData.sublistView(depthBytes);
        final values = Float32List(width * height);
        for (var i = 0; i < values.length; i++) {
          values[i] = data.getFloat32(i * 4, Endian.little);
        }
        depth = DepthFrame(
          valuesMeters: values,
          confidence: depthPayload['confidence'] as Uint8List,
          width: width,
          height: height,
          frameTimestampNs: (payload['frameTimestampNs'] as num).toInt(),
          imageTimestampNs: (depthPayload['imageTimestampNs'] as num).toInt(),
          isReprojected: depthPayload['isReprojected'] as bool? ?? false,
          isRaw: depthPayload['isRaw'] as bool? ?? false,
          confidenceAvailable: depthPayload['confidenceAvailable'] as bool? ?? false,
          intrinsics: readIntrinsics(depthPayload['intrinsics']),
        );
      }
      final depthSupport = switch (payload['depthSupport']) {
        'rawOnly' => VrixDepthSupport.rawOnly,
        'automatic' => VrixDepthSupport.automatic,
        'unsupported' => VrixDepthSupport.unsupported,
        _ => VrixDepthSupport.notChecked,
      };
      final captured = CapturedFrame(
        rgbBytes: rgbBytes,
        frameTimestampNs: (payload['frameTimestampNs'] as num).toInt(),
        rgbTimestampNs: (payload['rgbTimestampNs'] as num).toInt(),
        rgbIntrinsics: readIntrinsics(payload['rgbIntrinsics']),
        cameraPose: pose,
        trackingState: payload['trackingState'] == 'tracking'
            ? VrixTrackingState.tracking
            : VrixTrackingState.paused,
        depthSupport: depthSupport,
        depth: depth,
      );
      captured.validate();

      final support = await getApplicationSupportDirectory();
      final captureDirectory = Directory('${support.path}/vrix_scans/_captures');
      await captureDirectory.create(recursive: true);
      final path = '${captureDirectory.path}/capture-${DateTime.now().microsecondsSinceEpoch}.jpg';
      final imageFile = File(path);
      await imageFile.writeAsBytes(rgbBytes, flush: true);

      final codec = await ui.instantiateImageCodec(rgbBytes);
      final imageFrame = await codec.getNextFrame();
      final width = imageFrame.image.width;
      final height = imageFrame.image.height;
      imageFrame.image.dispose();
      codec.dispose();

      if (width != captured.rgbWidth || height != captured.rgbHeight) {
        throw StateError('Decoded RGB dimensions differ from the ARCore image intrinsics.');
      }
      final segmenter = await InteractiveSegmenter.create(
        InteractiveSegmenterOptions(model: VisionModels.interactiveSegmenter),
      );
      await segmenter.setImage(VisionImage.fromFile(path));
      final previous = _segmenter;
      _segmenter = segmenter;
      await previous?.dispose();
      _maskImage?.dispose();
      if (!mounted) {
        await segmenter.dispose();
        return;
      }
      setState(() {
        _photoPath = path;
        _imageWidth = width;
        _imageHeight = height;
        _cameraPose = captured.cameraPose.toList(growable: false);
        _capturedFrame = captured;
        _maskImage = null;
        _maskWidth = 1;
        _maskHeight = 1;
        _strokes.clear();
        _saved = false;
        _status = depth == null
            ? 'تم التقاط RGB مع وضعية معايرة. هذا الجهاز لم يوفّر عمقاً في الإطار الحالي.'
            : 'تم التقاط RGB وDepth من إطار ARCore واحد. المس داخل الجسم لعزله.';
      });
    } catch (error) {
      if (mounted) setState(() {
        _error = error.toString();
        _status = 'تعذّر التقاط إطار ARCore متزامن. تحقق من التتبع والعمق ثم أعد المحاولة.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPrompt(Offset position, Size viewport) async {
    final segmenter = _segmenter;
    if (_busy || segmenter == null || _photoPath == null) return;
    final rect = _imageRect(viewport);
    if (!rect.contains(position)) return;
    final x = ((position.dx - rect.left) / rect.width).clamp(0.0, 1.0);
    final y = ((position.dy - rect.top) / rect.height).clamp(0.0, 1.0);
    final stroke = Stroke(
      brushMode: BrushMode.positive,
      points: [
        NormalizedKeypoint(x: (x - .008).clamp(0.0, 1.0), y: y),
        NormalizedKeypoint(x: (x + .008).clamp(0.0, 1.0), y: y),
      ],
    );
    setState(() {
      _busy = true;
      _saved = false;
      _promptX = x;
      _promptY = y;
      _strokes.add(stroke);
      _status = 'جارٍ تحديث قناع الجسم محلياً…';
    });
    try {
      final mask = await segmenter.segment(List<Stroke>.unmodifiable(_strokes));
      final rgba = Uint8List(mask.width * mask.height * 4);
      for (var i = 0; i < mask.confidence.length; i++) {
        final confidence = mask.confidence[i].clamp(0.0, 1.0);
        final offset = i * 4;
        rgba[offset] = 45;
        rgba[offset + 1] = 220;
        rgba[offset + 2] = 195;
        rgba[offset + 3] = confidence >= 0.35 ? (confidence * 165).round() : 0;
      }
      final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: mask.width,
        height: mask.height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final codec = await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();
      final previous = _maskImage;
      if (mounted) {
        setState(() {
          _maskImage = frame.image;
          _maskWidth = mask.width;
          _maskHeight = mask.height;
          _status = 'تم تحديث القناع. احفظ المنظور ثم تحرّك إلى زاوية جديدة.';
        });
      } else {
        frame.image.dispose();
      }
      previous?.dispose();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    } catch (error) {
      if (mounted) setState(() {
        if (_strokes.isNotEmpty) _strokes.removeLast();
        _error = error.toString();
        _status = 'تعذّر إنشاء القناع. جرّب نقطة أخرى.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveView() async {
    final path = _photoPath;
    final mask = _maskImage;
    final pose = _cameraPose;
    final capturedFrame = _capturedFrame;
    final promptX = _promptX;
    final promptY = _promptY;
    if (_busy || path == null || mask == null || pose == null || capturedFrame == null || promptX == null || promptY == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = 'جارٍ حفظ الصورة والقناع ووضعية الكاميرا…';
    });
    try {
      final data = await mask.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('تعذّر ترميز قناع PNG.');
      final store = _store ??= await ObjectScanStore.create(
        displayName: 'VRIX scanned object',
      );
      await store.addView(ObjectScanView(
        imageFile: File(path),
        maskPng: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        width: _imageWidth,
        height: _imageHeight,
        maskWidth: _maskWidth,
        maskHeight: _maskHeight,
        promptX: promptX,
        promptY: promptY,
        cameraPose: pose,
        cameraPoseSynchronized: true,
        capturedFrame: capturedFrame,
      ));
      if (mounted) setState(() {
        _saved = true;
        _status = 'حُفظ المنظور ${store.viewCount}. حرّك الهاتف حول الجسم والتقط زاوية مختلفة.';
      });
    } catch (error) {
      if (mounted) setState(() {
        _error = error.toString();
        _status = 'تعذّر حفظ المنظور.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finishScan() async {
    final store = _store;
    if (_busy || store == null) return;
    setState(() {
      _busy = true;
      _status = 'جارٍ إغلاق جلسة الالتقاط…';
    });
    try {
      final result = await store.complete();
      if (mounted) setState(() {
        _completed = true;
        _status = 'اكتمل حفظ ${result.viewCount} مناظير RGB-D. إعادة بناء المجسم لم تبدأ بعد.';
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reconstructScan() async {
    final store = _store;
    if (_busy || !_completed || store == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = 'جارٍ دمج بيانات RGB-D وإعادة بناء السطح وتصدير GLB…';
    });
    try {
      final result = await const ObjectScanReconstructionService().reconstruct(store.snapshot);
      final physics = PhysicsSceneService();
      try {
        result.mesh.bakeStaticCollider(physics, id: 'scan-${store.id}');
      } catch (_) {
        physics.dispose();
        rethrow;
      }
      _physicsScene?.dispose();
      _physicsScene = physics;
      if (mounted) setState(() {
        _reconstruction = result;
        _status = 'تم إنشاء GLB ومعاينة Collider ثابتة عبر Jolt. المثلثات: ${result.mesh.triangleCount} · النقاط: ${result.inputPointCount}. يلزم فحص جودة السطح على الجهاز قبل اعتماده.';
      });
    } catch (error) {
      if (mounted) setState(() {
        _error = error.toString();
        _status = 'تعذرت إعادة البناء. لم يتم اعتماد مجسم أو Collider غير صالح.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearCurrentView() async {
    if (_busy) return;
    _maskImage?.dispose();
    _maskImage = null;
    final segmenter = _segmenter;
    _segmenter = null;
    await segmenter?.dispose();
    if (mounted) setState(() {
      _photoPath = null;
      _cameraPose = null;
      _capturedFrame = null;
      _promptX = null;
      _promptY = null;
      _strokes.clear();
      _saved = false;
      _status = 'عد إلى عرض AR ثم التقط منظوراً جديداً.';
    });
  }

  @override
  void dispose() {
    _maskImage?.dispose();
    final segmenter = _segmenter;
    if (segmenter != null) unawaited(segmenter.dispose());
    final session = _session;
    if (session != null) unawaited(session.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('مسح الأجسام عبر ARCore')),
    body: Stack(
      children: [
        Positioned.fill(
          child: ARView(
            showPlatformType: false,
            planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical,
            onARViewCreated: _onArCreated,
          ),
        ),
        if (_photoPath != null)
          Positioned.fill(
            child: LayoutBuilder(builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => _addPrompt(details.localPosition, size),
                child: ColoredBox(
                  color: AppColors.background,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(File(_photoPath!), fit: BoxFit.contain),
                      if (_maskImage != null)
                        RawImage(image: _maskImage, fit: BoxFit.contain),
                      if (_busy)
                        const ColoredBox(
                          color: Color(0x55000000),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                    ],
                  ),
                ),
              );
            }),
          ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: SafeArea(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xEE101A28),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_status, style: const TextStyle(fontSize: 11, height: 1.5)),
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 10)),
                  const SizedBox(height: 10),
                  if (_photoPath == null)
                    FilledButton.icon(
                      onPressed: _busy || _completed ? null : _captureView,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: Text(_completed ? 'اكتملت جلسة المسح' : 'التقاط منظور AR'),
                    )
                  else ...[
                    FilledButton.icon(
                      onPressed: _busy || _saved || _maskImage == null ? null : _saveView,
                      icon: const Icon(Icons.save_alt_rounded),
                      label: Text(_saved ? 'تم حفظ المنظور' : 'حفظ المنظور وبيانات RGB-D'),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _clearCurrentView,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('العودة إلى AR'),
                          ),
                        ),
                        if ((_store?.viewCount ?? 0) >= 3 && !_completed) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : _finishScan,
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('إنهاء المسح'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                  if (_completed && _reconstruction == null)
                    FilledButton.icon(
                      onPressed: _busy ? null : _reconstructScan,
                      icon: const Icon(Icons.view_in_ar_rounded),
                      label: const Text('إعادة بناء Mesh وتصدير GLB وCollider'),
                    ),
                  if (_reconstruction != null)
                    Text('ملف GLB: ${_reconstruction!.glbFile.path}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.success, fontSize: 10)),
                  if (_photoPath == null && (_store?.viewCount ?? 0) > 0)
                    Text('المناظير المحفوظة: ${_store!.viewCount}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.success, fontSize: 10)),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
