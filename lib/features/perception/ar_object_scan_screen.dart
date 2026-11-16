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
import '../../services/object_scan_store.dart';

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
  double? _promptX;
  double? _promptY;
  final List<Stroke> _strokes = [];
  bool _busy = false;
  bool _saved = false;
  bool _completed = false;
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
      _status = 'جارٍ التقاط الصورة ووضعية الكاميرا من جلسة ARCore…';
    });
    try {
      // The plugin exposes the current AR camera pose and a PixelCopy snapshot.
      // Request pose once per user capture, never from a per-frame timer.
      final pose = await session.getCameraPose();
      if (pose == null) {
        throw StateError('لا توجد وضعية كاميرا موثوقة بعد. حرّك الهاتف وانتظر استقرار التتبع.');
      }
      final provider = await session.snapshot();
      if (provider is! MemoryImage) {
        throw StateError('صيغة لقطة AR غير مدعومة في هذا النظام.');
      }
      final support = await getApplicationSupportDirectory();
      final captureDirectory = Directory('${support.path}/vrix_scans/_captures');
      await captureDirectory.create(recursive: true);
      final path = '${captureDirectory.path}/capture-${DateTime.now().microsecondsSinceEpoch}.png';
      final imageFile = File(path);
      await imageFile.writeAsBytes(provider.bytes, flush: true);

      final codec = await ui.instantiateImageCodec(provider.bytes);
      final frame = await codec.getNextFrame();
      final width = frame.image.width;
      final height = frame.image.height;
      frame.image.dispose();
      codec.dispose();

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
        _cameraPose = pose.storage.toList(growable: false);
        _maskImage = null;
        _maskWidth = 1;
        _maskHeight = 1;
        _strokes.clear();
        _saved = false;
        _status = 'المس داخل الجسم لعزله. أضف نقاطاً موجبة أو سالبة لتحسين القناع.';
      });
    } catch (error) {
      if (mounted) setState(() {
        _error = error.toString();
        _status = 'تعذّر التقاط منظور AR. تحقق من التتبع ثم أعد المحاولة.';
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
    final promptX = _promptX;
    final promptY = _promptY;
    if (_busy || path == null || mask == null || pose == null || promptX == null || promptY == null) return;
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
        _status = 'اكتمل التقاط ${result.viewCount} مناظير مع وضعيات ARCore. العمق وإعادة البناء لم يبدآ بعد.';
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
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
                      label: Text(_saved ? 'تم حفظ المنظور' : 'حفظ المنظور مع وضعية الكاميرا'),
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
