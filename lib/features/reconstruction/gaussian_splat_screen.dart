import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/app_theme.dart';

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
                            Wrap(
                              spacing: 7,
                              children: const [
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
                  _status,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 51,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _importWorld,
                    icon: Icon(
                      _busy ? Icons.hourglass_top_rounded : Icons.folder_open_rounded,
                    ),
                    label: Text(
                      _busy ? 'جارٍ تجهيز الملف…' : 'استيراد مشهد ثلاثي الأبعاد',
                    ),
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
