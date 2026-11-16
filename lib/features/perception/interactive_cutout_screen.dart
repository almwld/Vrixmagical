import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mediapipe_vision/mediapipe_vision.dart';

import '../../app/app_theme.dart';

class InteractiveCutoutScreen extends StatefulWidget {
  const InteractiveCutoutScreen({super.key});

  @override
  State<InteractiveCutoutScreen> createState() => _InteractiveCutoutScreenState();
}

class _InteractiveCutoutScreenState extends State<InteractiveCutoutScreen> {
  CameraController? _camera;
  InteractiveSegmenter? _segmenter;
  String? _photoPath;
  ui.Image? _maskImage;
  int _imageWidth = 1;
  int _imageHeight = 1;
  final List<Stroke> _strokes = [];
  bool _busy = false;
  bool _excludeMode = false;
  String _status = 'التقط صورة ثم المس الجسم الذي تريد عزله.';
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('لا توجد كاميرا متاحة.');
      final selected = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final camera = CameraController(
        selected,
        ResolutionPreset.high,
        enableAudio: false,
      );
      _camera = camera;
      await camera.initialize();
      if (mounted) setState(() => _status = 'الكاميرا جاهزة. التقط صورة واضحة للجسم.');
    } catch (error) {
      if (mounted) setState(() {
        _error = error.toString();
        _status = 'تعذّر تشغيل الكاميرا.';
      });
    }
  }

  Future<void> _capture() async {
    final camera = _camera;
    if (_busy || camera == null || !camera.value.isInitialized) return;
    setState(() {
      _busy = true;
      _status = 'جارٍ التقاط الصورة وتجهيز نموذج العزل…';
      _error = null;
    });
    try {
      final photo = await camera.takePicture();
      final bytes = await File(photo.path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final width = frame.image.width;
      final height = frame.image.height;
      frame.image.dispose();
      codec.dispose();

      final segmenter = await InteractiveSegmenter.create(
        InteractiveSegmenterOptions(model: VisionModels.interactiveSegmenter),
      );
      await segmenter.setImage(VisionImage.fromFile(photo.path));
      await camera.dispose();
      _camera = null;
      if (!mounted) {
        await segmenter.dispose();
        return;
      }
      setState(() {
        _photoPath = photo.path;
        _imageWidth = width;
        _imageHeight = height;
        _segmenter = segmenter;
        _strokes.clear();
        _status = 'المس داخل الجسم لإضافته إلى التحديد. يمكنك إضافة نقاط لتحسين الحواف.';
      });
    } catch (error) {
      if (mounted) setState(() {
        _error = error.toString();
        _status = 'تعذّر تجهيز الصورة للعزل.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Rect _imageRect(Size viewport) {
    final fitted = applyBoxFit(
      BoxFit.contain,
      Size(_imageWidth.toDouble(), _imageHeight.toDouble()),
      viewport,
    );
    return Alignment.center.inscribe(fitted.destination, Offset.zero & viewport);
  }

  Future<void> _addPoint(Offset localPosition, Size viewport) async {
    final segmenter = _segmenter;
    if (_busy || segmenter == null) return;
    final rect = _imageRect(viewport);
    if (!rect.contains(localPosition)) return;
    final x = ((localPosition.dx - rect.left) / rect.width).clamp(0.0, 1.0);
    final y = ((localPosition.dy - rect.top) / rect.height).clamp(0.0, 1.0);

    final dx = 0.008;
    final points = [
      NormalizedKeypoint(x: (x - dx).clamp(0.0, 1.0), y: y),
      NormalizedKeypoint(x: (x + dx).clamp(0.0, 1.0), y: y),
    ];
    setState(() {
      _busy = true;
      _status = _excludeMode ? 'جارٍ إزالة المنطقة المحددة من القناع…' : 'جارٍ عزل الجسم محلياً…';
      _strokes.add(Stroke(
        brushMode: _excludeMode ? BrushMode.negative : BrushMode.positive,
        points: points,
      ));
    });

    try {
      final mask = await segmenter.segment(List<Stroke>.unmodifiable(_strokes));
      final rgba = Uint8List(mask.width * mask.height * 4);
      for (var i = 0; i < mask.confidence.length; i++) {
        final confidence = mask.confidence[i].clamp(0.0, 1.0);
        final offset = i * 4;
        rgba[offset] = 50;
        rgba[offset + 1] = 238;
        rgba[offset + 2] = 211;
        rgba[offset + 3] = confidence >= 0.35
            ? (confidence * 175).round()
            : 0;
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
          _status = 'تم تحديث القناع. أضف نقاطاً أخرى أو أزل مناطق غير مرغوبة.';
        });
      } else {
        frame.image.dispose();
      }
      previous?.dispose();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    } catch (error) {
      if (mounted) {
        setState(() {
          if (_strokes.isNotEmpty) _strokes.removeLast();
          _error = error.toString();
          _status = 'تعذّر تحديث القناع. حاول اختيار نقطة أخرى.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetSelection() async {
    final segmenter = _segmenter;
    final path = _photoPath;
    if (_busy || segmenter == null || path == null) return;
    setState(() {
      _busy = true;
      _strokes.clear();
      _error = null;
    });
    try {
      await segmenter.setImage(VisionImage.fromFile(path));
      _maskImage?.dispose();
      if (mounted) setState(() {
        _maskImage = null;
        _status = 'تمت إعادة التهيئة. المس الجسم لبدء تحديد جديد.';
      });
    } catch (error) {
      if (mounted) setState(() => _status = 'تعذّرت إعادة التهيئة: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retake() async {
    if (_busy) return;
    final segmenter = _segmenter;
    _segmenter = null;
    await segmenter?.dispose();
    _maskImage?.dispose();
    _maskImage = null;
    if (mounted) {
      setState(() {
        _photoPath = null;
        _strokes.clear();
        _error = null;
        _status = 'أعد توجيه الكاميرا إلى الجسم ثم التقط صورة.';
      });
    }
    await _initializeCamera();
  }

  @override
  void dispose() {
    _camera?.dispose();
    final segmenter = _segmenter;
    if (segmenter != null) {
      segmenter.dispose();
    }
    _maskImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final photoPath = _photoPath;
    return Scaffold(
      appBar: AppBar(
        title: const Text('العزل التفاعلي'),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Text(
                  'MAGIC TOUCH',
                  style: TextStyle(
                    color: AppColors.secondary,
                    fontSize: 8,
                    letterSpacing: .8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(14, 4, 14, 12),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.border),
              ),
              child: photoPath == null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        if (camera != null && camera.value.isInitialized)
                          CameraPreview(camera)
                        else
                          const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                            ),
                          ),
                        Positioned(
                          top: 13,
                          left: 13,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xDD101A28),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'CAMERA INPUT',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 8,
                                letterSpacing: 1,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final size = Size(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        );
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (details) =>
                              _addPoint(details.localPosition, size),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(File(photoPath), fit: BoxFit.contain),
                              if (_maskImage != null)
                                RawImage(
                                  image: _maskImage,
                                  fit: BoxFit.contain,
                                ),
                              Positioned(
                                top: 13,
                                left: 13,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xDD101A28),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: AppColors.primary.withValues(
                                        alpha: .3,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    _excludeMode ? 'REMOVE REGION' : 'TAP TO SELECT',
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 8,
                                      letterSpacing: .8,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                              if (_busy)
                                const ColoredBox(
                                  color: Color(0x66080D16),
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 15, 18, 19),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome_rounded,
                      color: AppColors.primary,
                      size: 19,
                    ),
                    const SizedBox(width: 9),
                    const Expanded(
                      child: Text(
                        'تحديد ذكي متعدد النقاط',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    if (photoPath != null)
                      Text(
                        '${_strokes.length} نقطة',
                        style: const TextStyle(
                          color: AppColors.secondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _status,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 10,
                    height: 1.6,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: Color(0xFFFF8A80),
                      fontSize: 10,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                if (photoPath == null)
                  SizedBox(
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _capture,
                      icon: const Icon(Icons.camera_alt_rounded),
                      label: const Text('التقاط صورة للعنصر'),
                    ),
                  )
                else ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => setState(
                                  () => _excludeMode = !_excludeMode,
                                ),
                          icon: Icon(
                            _excludeMode
                                ? Icons.add_circle_outline_rounded
                                : Icons.remove_circle_outline_rounded,
                          ),
                          label: Text(
                            _excludeMode ? 'إضافة منطقة' : 'استبعاد منطقة',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'إعادة القناع',
                        onPressed: _busy ? null : _resetSelection,
                        icon: const Icon(Icons.restart_alt_rounded),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filledTonal(
                        tooltip: 'صورة جديدة',
                        onPressed: _busy ? null : _retake,
                        icon: const Icon(Icons.camera_alt_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'تتم معالجة القناع محلياً على الجهاز',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.success,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
