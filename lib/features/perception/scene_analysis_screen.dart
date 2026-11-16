import 'package:camera/camera.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_theme.dart';
import '../../services/scene_perception_service.dart';

class SceneAnalysisScreen extends StatefulWidget {
  const SceneAnalysisScreen({super.key});

  @override
  State<SceneAnalysisScreen> createState() => _SceneAnalysisScreenState();
}

class _SceneAnalysisScreenState extends State<SceneAnalysisScreen> {
  CameraController? _camera;
  bool _busy = false;
  bool _cameraFailed = false;
  String _status = 'وجّه الكاميرا نحو المشهد ثم ابدأ التحليل المحلي.';
  List<String> _labels = const [];

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('لا توجد كاميرا متاحة.');
      final selected = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      _camera = controller;
      await controller.initialize();
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        setState(() {
          _cameraFailed = true;
          _status = 'تعذّر تشغيل الكاميرا: $error';
        });
      }
    }
  }

  Future<void> _analyze() async {
    final camera = _camera;
    if (_busy || camera == null || !camera.value.isInitialized) return;
    setState(() {
      _busy = true;
      _status = 'جارٍ تحليل الصورة باستخدام نماذج الرؤية المحلية…';
      _labels = const [];
    });
    try {
      final photo = await camera.takePicture();
      final result = await ScenePerceptionService.analyze(photo.path);
      if (!mounted) return;
      setState(() {
        _labels = result.labels;
        _status =
            'اكتمل التحليل: ${result.objectCount} أجسام مكتشفة · قناع التقسيم ${result.maskWidth}×${result.maskHeight}.';
      });
    } catch (error) {
      if (mounted) setState(() => _status = 'تعذّر التحليل: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final ready = camera != null && camera.value.isInitialized;
    return Scaffold(
      appBar: AppBar(
        title: const Text('فهم المشهد'),
        actions: const [
          Padding(
            padding: EdgeInsetsDirectional.only(end: 18),
            child: Center(child: _LiveBadge()),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: AppColors.border),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (ready)
                    CameraPreview(camera)
                  else
                    _CameraPlaceholder(
                      failed: _cameraFailed,
                      message: _cameraFailed
                          ? 'تحقق من إذن الكاميرا ثم أعد فتح الأداة.'
                          : 'جارٍ تهيئة الكاميرا الخلفية…',
                    ),
                  const Positioned(
                    top: 14,
                    left: 14,
                    child: _OverlayTag(
                      icon: Icons.center_focus_strong_rounded,
                      label: 'SCENE PERCEPTION',
                    ),
                  ),
                  if (_busy)
                    const ColoredBox(
                      color: Color(0x99080D16),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: AppColors.primary),
                            SizedBox(height: 14),
                            Text(
                              'تحليل المشهد…',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const Positioned(
                    right: 14,
                    bottom: 14,
                    child: _OverlayTag(
                      icon: Icons.memory_rounded,
                      label: 'ON-DEVICE AI',
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(25),
              ),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'نتائج الإدراك',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  _status,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    height: 1.6,
                  ),
                ),
                if (_labels.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _labels
                        .map(
                          (label) => Chip(
                            avatar: const Icon(
                              Icons.check_circle_rounded,
                              size: 15,
                              color: AppColors.success,
                            ),
                            label: Text(label),
                            backgroundColor: AppColors.surfaceElevated,
                            side: const BorderSide(color: AppColors.border),
                          ),
                        )
                        .toList(),
                  ),
                ],
                const SizedBox(height: 15),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: ready && !_busy ? _analyze : null,
                    icon: Icon(
                      _busy
                          ? Icons.hourglass_top_rounded
                          : Icons.document_scanner_rounded,
                    ),
                    label: Text(_busy ? 'جارٍ التحليل…' : 'التقاط وتحليل المشهد'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: AppColors.success.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: AppColors.success.withValues(alpha: .22)),
    ),
    child: const Row(
      children: [
        Icon(Icons.circle, size: 6, color: AppColors.success),
        SizedBox(width: 6),
        Text(
          'VISION LAB',
          style: TextStyle(
            color: AppColors.success,
            fontSize: 9,
            letterSpacing: 1,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _OverlayTag extends StatelessWidget {
  const _OverlayTag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xDD101A28),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.primary, size: 13),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 8,
            letterSpacing: .7,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _CameraPlaceholder extends StatelessWidget {
  const _CameraPlaceholder({required this.failed, required this.message});

  final bool failed;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            failed ? Icons.no_photography_rounded : Icons.camera_alt_outlined,
            color: failed ? AppColors.muted : AppColors.primary,
            size: 48,
          ),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, height: 1.6),
          ),
        ],
      ),
    ),
  );
}
