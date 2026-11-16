import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../../services/scene_perception_service.dart';

class SceneAnalysisScreen extends StatefulWidget {
  const SceneAnalysisScreen({super.key});
  @override
  State<SceneAnalysisScreen> createState() => _SceneAnalysisScreenState();
}

class _SceneAnalysisScreenState extends State<SceneAnalysisScreen> {
  CameraController? _camera;
  bool _busy = false;
  String _status = 'التقط صورة لاكتشاف الأجسام وتحليل التقسيم محلياً.';
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
      final controller = CameraController(selected, ResolutionPreset.medium, enableAudio: false);
      _camera = controller;
      await controller.initialize();
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) setState(() => _status = 'تعذّر تشغيل الكاميرا: ' + error.toString());
    }
  }

  Future<void> _analyze() async {
    final camera = _camera;
    if (_busy || camera == null || !camera.value.isInitialized) return;
    setState(() {
      _busy = true;
      _status = 'جارٍ تحليل الصورة بنماذج محلية…';
      _labels = const [];
    });
    try {
      final photo = await camera.takePicture();
      final result = await ScenePerceptionService.analyze(photo.path);
      if (!mounted) return;
      setState(() {
        _labels = result.labels;
        _status = 'اكتمل التحليل: ' + result.objectCount.toString() +
            ' أجسام مكتشفة، وقناع تقسيم ' + result.maskWidth.toString() + '×' + result.maskHeight.toString() + '.';
      });
    } catch (error) {
      if (mounted) setState(() => _status = 'تعذّر التحليل: ' + error.toString());
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
    return Scaffold(
      appBar: AppBar(title: const Text('فهم المشهد والعزل')),
      body: Column(children: [
        Expanded(
          child: camera != null && camera.value.isInitialized
              ? CameraPreview(camera)
              : const Center(child: CircularProgressIndicator()),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(_status, style: const TextStyle(height: 1.5)),
            if (_labels.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: _labels.map((label) => Chip(label: Text(label))).toList()),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _analyze,
              icon: const Icon(Icons.document_scanner_outlined),
              label: Text(_busy ? 'جارٍ التحليل…' : 'التقاط وتحليل'),
            ),
          ]),
        ),
      ]),
    );
  }
}
