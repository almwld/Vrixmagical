import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_theme.dart';
import '../../services/object_library_catalog.dart';
import '../../services/model_arabic_labels.dart';
import '../studio/ar_scene_screen.dart';

class ObjectLibraryScreen extends StatefulWidget {
  const ObjectLibraryScreen({super.key});

  @override
  State<ObjectLibraryScreen> createState() => _ObjectLibraryScreenState();
}

class _ObjectLibraryScreenState extends State<ObjectLibraryScreen> {
  late Future<ObjectLibraryStore> _storeFuture;
  String _query = '';
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _storeFuture = ObjectLibraryStore.open();
  }

  Future<void> _importModel() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final selection = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['glb', 'gltf'],
      );
      final path = selection?.path;
      if (path == null) return;
      final store = await _storeFuture;
      final imported = await store.importModel(path);
      if (!mounted) return;
      setState(() => _storeFuture = Future.value(store));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم استيراد ${imported.object.displayName}')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر استيراد النموذج: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }


  String _absolutePath(ObjectLibraryStore store, CatalogAsset asset) =>
      '${store.rootDirectory.path}/${asset.object.meshPath}';

  Future<void> _openInEngine(ObjectLibraryStore store, CatalogAsset asset) async {
    final path = _absolutePath(store, asset);
    if (!await File(path).exists()) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ملف المجسم غير موجود في التخزين المحلي.')),
      );
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ArSceneScreen(modelPath: path),
    ));
  }

  Future<void> _downloadModel(ObjectLibraryStore store, CatalogAsset asset) async {
    try {
      final path = _absolutePath(store, asset);
      final file = File(path);
      if (!await file.exists()) throw const FileSystemException('ملف GLB غير موجود.');
      final bytes = await file.readAsBytes();
      final name = asset.object.displayName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_') + '.glb';
      final saved = await FilePicker.saveFile(fileName: name, bytes: bytes, type: FileType.custom, allowedExtensions: const ['glb']);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(saved == null ? 'أُلغي التصدير.' : 'تم حفظ ملف المجسم.')),
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر تنزيل ملف GLB: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('مكتبة الأصول'),
          actions: [
            IconButton(
              tooltip: 'استيراد GLB / GLTF',
              onPressed: _importing ? null : _importModel,
              icon: _importing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_box_outlined),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: FutureBuilder<ObjectLibraryStore>(
          future: _storeFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'تعذّر تحميل مكتبة الأصول: ${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            final store = snapshot.data!;
            final assets = store.catalog.search(query: _query);
            return ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF203B54), Color(0xFF172438)],
                    ),
                    borderRadius: BorderRadius.circular(23),
                    border: Border.all(
                      color: AppColors.secondary.withValues(alpha: .22),
                    ),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.view_in_ar_rounded,
                          color: AppColors.secondary, size: 27),
                      SizedBox(height: 18),
                      Text(
                        'مكتبة الأجسام التفاعلية',
                        style: TextStyle(
                            fontSize: 21, fontWeight: FontWeight.w900),
                      ),
                      SizedBox(height: 7),
                      Text(
                        'استورد نماذج GLB وGLTF محلياً، واحتفظ بهويتها ووسومها وملفها الفيزيائي في فهرس واحد.',
                        style: TextStyle(
                            color: Color(0xFFB5C5D8),
                            fontSize: 11,
                            height: 1.7),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: 'ابحث بالاسم أو الوسوم الدلالية',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Text('الأصول المتاحة',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w900)),
                    const Spacer(),
                    Text(
                      '${assets.length} أصل',
                      style: const TextStyle(
                          color: AppColors.muted, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (assets.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.view_in_ar_outlined,
                            size: 34, color: AppColors.muted),
                        SizedBox(height: 10),
                        Text(
                          'مكتبتك فارغة حالياً',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'اضغط زر الإضافة لاستيراد نموذج GLB أو GLTF. ستُحفظ الملفات محلياً مع بياناتها.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                              height: 1.6),
                        ),
                      ],
                    ),
                  )
                else
                  ...assets.map((asset) => Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(17),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.view_in_ar_rounded,
                                color: AppColors.primary, size: 28),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(ModelArabicLabels.displayName(asset.object.displayName),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${asset.category} · ${asset.sourceName} · ${asset.license}',
                                    style: const TextStyle(
                                        color: AppColors.muted, fontSize: 10),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    asset.object.tags.join(' · '),
                                    style: const TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 10),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                tooltip: 'فتح في محرك الواقع المعزز',
                                onPressed: () => _openInEngine(store, asset),
                                icon: const Icon(Icons.view_in_ar_rounded, color: AppColors.primary),
                              ),
                              IconButton(
                                tooltip: 'تنزيل ملف GLB',
                                onPressed: () => _downloadModel(store, asset),
                                icon: const Icon(Icons.download_rounded, color: AppColors.secondary),
                              ),
                            ]),
                          ],
                        ),
                      )),
              ],
            );
          },
        ),
      );
}
