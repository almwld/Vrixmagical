import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('مشاهد Gaussian Splat')),
      body: Column(children: [
        Expanded(
          child: _worldPath != null && supported
              ? ClipRect(
                  child: AndroidView(
                    key: ValueKey(_worldPath),
                    viewType: 'virxmagical/splat_view',
                    creationParams: {'worldPath': _worldPath},
                    creationParamsCodec: const StandardMessageCodec(),
                  ),
                )
              : Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111B2A),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFF29465B)),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.blur_on_rounded, size: 72, color: Color(0xFF55E3D4)),
                    const SizedBox(height: 16),
                    const Text('عارض المشاهد المكانية', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 26),
                      child: Text(
                        supported
                            ? 'استورد ملف SPZ أو LODSPLAT لعرض سحابة النقاط ثلاثية الأبعاد.'
                            : 'يتطلب هذا العارض هاتف Android بمعمارية arm64 ودعم Vulkan 1.1 وAndroid 10 أو أحدث.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF91A7BC), height: 1.6),
                      ),
                    ),
                  ]),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_worldName != null)
              Text('المشهد: ' + _worldName!, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Text(_status, style: const TextStyle(color: Color(0xFF91A7BC), fontSize: 12, height: 1.5)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _importWorld,
              icon: const Icon(Icons.folder_open_rounded),
              label: Text(_busy ? 'جارٍ تجهيز الملف…' : 'استيراد مشهد ثلاثي الأبعاد'),
            ),
          ]),
        ),
      ]),
    );
  }
}
