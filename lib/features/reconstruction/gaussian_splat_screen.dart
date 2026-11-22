import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/app_theme.dart';
import '../../services/splatkit_view_controller.dart';
import '../../services/splat_tiled_world_importer.dart';

class GaussianSplatScreen extends StatefulWidget {
  const GaussianSplatScreen({super.key});
  @override
  State<GaussianSplatScreen> createState() => _GaussianSplatScreenState();
}

class _GaussianSplatScreenState extends State<GaussianSplatScreen> {
  String? _worldPath;
  String? _worldName;
  String _status = 'استورد ملف SPZ أو LODSPLAT لعرض المشهد ثلاثي الأبعاد.';
  bool _busy = false;
  SplatKitViewController? _controller;

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _onPlatformViewCreated(int viewId) {
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    final controller = SplatKitViewController(viewId)
      ..addListener(_onControllerChanged);
    _controller = controller;
    controller.connect();
  }

  Future<void> _importCollider() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      final selected = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['glb'],
        dialogTitle: 'اختر Collider بصيغة GLB',
      );
      if (selected == null || selected.path == null) return;
      final directory = await getApplicationDocumentsDirectory();
      final copied = await File(selected.path!).copy(
        directory.path + '/collider_' +
            DateTime.now().millisecondsSinceEpoch.toString() + '.glb',
      );
      await controller.loadCollider(copied.path);
    } catch (error) {
      if (mounted) setState(() => _status = 'تعذّر تحميل Collider: ' + error.toString());
    }
  }

  Future<void> _setQuality(String value) async {
    await _controller?.applyQuality(value);
  }

  Future<void> _importTiledWorld() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = 'اختر مجلد العالم المقسّم…';
    });
    try {
      final selectedDirectory = await FilePicker.getDirectoryPath(
        dialogTitle: 'اختر مجلد Gaussian Splat Tileset',
      );
      if (selectedDirectory == null) return;
      final documents = await getApplicationDocumentsDirectory();
      final imported = await const SplatTiledWorldImporter().copyDirectory(
        source: Directory(selectedDirectory),
        destinationRoot: documents,
        onProgress: (copied, total) {
          if (mounted && copied % 20 == 0) {
            setState(() => _status = 'نسخ ملفات العالم: $copied / $total');
          }
        },
      );
      _controller?.removeListener(_onControllerChanged);
      _controller?.dispose();
      _controller = null;
      setState(() {
        _worldPath = imported.tilesetFile.path;
        _worldName = 'Tiled Gaussian World';
        _status = 'تم نسخ ${imported.fileCount} ملفاً؛ جارٍ تحميل Tileset.';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _status = 'تعذّر استيراد Tileset: ' + error.toString());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importWorld() async {
    if (kIsWeb || !Platform.isAndroid) {
      setState(() => _status = 'عارض Gaussian Splat الأصلي متاح حالياً على Android arm64 فقط.');
      return;
    }
    setState(() => _busy = true);
    try {
      final selected = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['spz', 'lodsplat'],
        dialogTitle: 'اختر مشهد Gaussian Splat',
      );
      if (selected == null) return;
      final sourcePath = selected.path;
      if (sourcePath == null) throw StateError('لم يتمكن مستعرض الملفات من إرجاع مسار الملف.');
      final directory = await getApplicationDocumentsDirectory();
      final extension = selected.extension?.toLowerCase() ?? 'spz';
      final safeName = 'world_' + DateTime.now().millisecondsSinceEpoch.toString() + '.' + extension;
      final copied = await File(sourcePath).copy(directory.path + '/' + safeName);
      if (!mounted) return;
      _controller?.removeListener(_onControllerChanged);
      _controller?.dispose();
      _controller = null;
      setState(() {
        _worldPath = copied.path;
        _worldName = selected.name;
        _status = 'تم تجهيز المشهد. جارٍ تحميل بيانات Gaussian Splat على GPU.';
      });
    } catch (error) {
      if (mounted) setState(() => _status = 'تعذّر استيراد المشهد: ' + error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final supported = !kIsWeb && Platform.isAndroid;
    final hasWorld = _worldPath != null && supported;
    return Scaffold(
      appBar: AppBar(
        title: const Text('مشاهد Gaussian Splat'),
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
                  'SPLAT VIEWER',
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
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: AppColors.border),
              ),
              child: hasWorld
                  ? AndroidView(
                      key: ValueKey(_worldPath),
                      viewType: 'virxmagical/splat_view',
                      creationParams: {'worldPath': _worldPath},
                      creationParamsCodec: const StandardMessageCodec(),
                      onPlatformViewCreated: _onPlatformViewCreated,
                    )
                  : Center(
                      child: Padding(
                        padding: const EdgeInsets.all(26),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 94,
                              height: 94,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.secondary.withValues(alpha: .18),
                                    AppColors.primary.withValues(alpha: .08),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(29),
                                border: Border.all(
                                  color: AppColors.secondary.withValues(alpha: .25),
                                ),
                              ),
                              child: const Icon(
                                Icons.blur_on_rounded,
                                size: 48,
                                color: AppColors.secondary,
                              ),
                            ),
                            const SizedBox(height: 22),
                            const Text(
                              'مساحة العرض المكاني',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 9),
                            Text(
                              supported
                                  ? 'استورد مشهداً بصيغة SPZ أو LODSPLAT لعرضه كسحابة نقاط ثلاثية الأبعاد.'
                                  : 'يتطلب العارض Android 10 أو أحدث، ومعمارية arm64 ودعم Vulkan 1.1.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.muted,
                                height: 1.7,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 20),
                            const Wrap(
                              spacing: 7,
                              children: [
                                _FormatTag(label: 'SPZ'),
                                _FormatTag(label: 'LODSPLAT'),
                                _FormatTag(label: 'VULKAN'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 15, 18, 20),
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
                if (_worldName != null) ...[
                  Row(
                    children: [
                      const Icon(
                        Icons.insert_drive_file_outlined,
                        color: AppColors.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _worldName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                ],
                Text(
                  _controller?.status ?? _status,
                  style: TextStyle(
                    color: _controller?.error != null
                        ? const Color(0xFFFF8A80)
                        : AppColors.muted,
                    fontSize: 11,
                    height: 1.55,
                  ),
                ),
                if (_controller?.error != null)
                  Text(
                    _controller!.error!,
                    style: const TextStyle(
                      color: Color(0xFFFF8A80),
                      fontSize: 10,
                    ),
                  ),
                if (_controller != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _controller!.gpuDescription.isEmpty
                        ? 'Vulkan device: checking…'
                        : _controller!.gpuDescription,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.secondary,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (_controller!.firstFrameReady)
                    Text(
                      'FPS ${(_controller!.stats['fps'] as num?)?.toStringAsFixed(1) ?? '—'}'
                      ' · GPU ${(_controller!.stats['gpuMillis'] as num?)?.toStringAsFixed(2) ?? '—'} ms'
                      ' · Loaded ${_controller!.stats['loadedSplats'] ?? 0}'
                      ' · Drawn ${_controller!.stats['drawnSplats'] ?? 0}',
                      style: const TextStyle(
                        color: AppColors.success,
                        fontSize: 9,
                      ),
                    ),
                  if (_controller!.capabilities.isNotEmpty)
                    Text(
                      'Vulkan · Subgroups: ${_controller!.capabilities['supportsSubgroups'] == true ? 'ON' : 'OFF'}'
                      ' · Hi-Z: ${_controller!.capabilities['supportsHiZOcclusion'] == true ? 'supported' : 'fallback'}'
                      ' · Max texture: ${_controller!.capabilities['maxTextureDimension'] ?? '—'}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 9,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text(
                        'الجودة',
                        style: TextStyle(fontSize: 10, color: AppColors.muted),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: _controller!.quality,
                        isDense: true,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(value: 'low', child: Text('LOW')),
                          DropdownMenuItem(value: 'medium', child: Text('MEDIUM')),
                          DropdownMenuItem(value: 'high', child: Text('HIGH')),
                          DropdownMenuItem(value: 'ultra', child: Text('ULTRA')),
                        ],
                        onChanged: (value) {
                          if (value != null) _setQuality(value);
                        },
                      ),
                      const Spacer(),
                      const Text(
                        'Motion',
                        style: TextStyle(fontSize: 10, color: AppColors.muted),
                      ),
                      Switch.adaptive(
                        value: _controller!.motionEnabled,
                        onChanged: (value) => _controller!.setMotionEnabled(value),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Text(
                        'Hi-Z occlusion',
                        style: TextStyle(fontSize: 10, color: AppColors.muted),
                      ),
                      Switch.adaptive(
                        value: _controller!.hiZOcclusionEnabled,
                        onChanged: _controller!.capabilities['supportsHiZOcclusion'] == true
                            ? (value) => _controller!.setHiZOcclusion(value)
                            : null,
                      ),
                      const Spacer(),
                      if (_controller!.renderPolicyAccepted != null)
                        Text(
                          _controller!.renderPolicyAccepted! ? 'Policy accepted' : 'Fallback',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 9,
                          ),
                        ),
                    ],
                  ),
                  if (_controller!.renderPolicyWarnings.isNotEmpty)
                    Text(
                      _controller!.renderPolicyWarnings.join(' · '),
                      style: const TextStyle(
                        color: Color(0xFFFFCC80),
                        fontSize: 9,
                      ),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        tooltip: 'Orbit left',
                        onPressed: () => _controller!.orbit(-0.18, 0),
                        icon: const Icon(Icons.rotate_left_rounded),
                      ),
                      IconButton(
                        tooltip: 'Orbit right',
                        onPressed: () => _controller!.orbit(0.18, 0),
                        icon: const Icon(Icons.rotate_right_rounded),
                      ),
                      IconButton(
                        tooltip: 'Orbit up',
                        onPressed: () => _controller!.orbit(0, 0.12),
                        icon: const Icon(Icons.keyboard_arrow_up_rounded),
                      ),
                      IconButton(
                        tooltip: 'Orbit down',
                        onPressed: () => _controller!.orbit(0, -0.12),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      ),
                      IconButton(
                        tooltip: 'Zoom out',
                        onPressed: () => _controller!.dolly(0.15),
                        icon: const Icon(Icons.zoom_out_rounded),
                      ),
                      IconButton(
                        tooltip: 'Zoom in',
                        onPressed: () => _controller!.dolly(-0.15),
                        icon: const Icon(Icons.zoom_in_rounded),
                      ),
                    ],
                  ),
                  OutlinedButton.icon(
                    onPressed: _importCollider,
                    icon: const Icon(Icons.layers_outlined, size: 16),
                    label: const Text('تحميل Collider GLB'),
                  ),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  height: 51,
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _importWorld,
                          icon: Icon(
                            _busy ? Icons.hourglass_top_rounded : Icons.file_open_rounded,
                          ),
                          label: Text(
                            _busy ? 'جارٍ تجهيز الملف…' : 'SPZ / LODSPLAT',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _importTiledWorld,
                          icon: const Icon(Icons.folder_open_rounded),
                          label: const Text('Tiled World'),
                        ),
                      ),
                    ],
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

class _FormatTag extends StatelessWidget {
  const _FormatTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.border),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: AppColors.secondary,
        fontSize: 8,
        fontWeight: FontWeight.w900,
        letterSpacing: .7,
      ),
    ),
  );

}
