import 'package:material_ui/material_ui.dart';

import '../../app/app_theme.dart';
import '../../services/object_library_catalog.dart';

class ObjectLibraryScreen extends StatefulWidget {
  const ObjectLibraryScreen({super.key});

  @override
  State<ObjectLibraryScreen> createState() => _ObjectLibraryScreenState();
}

class _ObjectLibraryScreenState extends State<ObjectLibraryScreen> {
  late Future<ObjectLibraryCatalog> _catalog;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _catalog = ObjectLibraryCatalog.load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('مكتبة الأصول'),
          actions: const [
            Padding(
              padding: EdgeInsetsDirectional.only(end: 18),
              child: Icon(Icons.inventory_2_outlined, color: AppColors.muted),
            ),
          ],
        ),
        body: FutureBuilder<ObjectLibraryCatalog>(
          future: _catalog,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'تعذّر تحميل فهرس الأصول: ${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            final catalog = snapshot.data!;
            final assets = catalog.search(query: _query);
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
                        'أصول ثلاثية الأبعاد بهوية موحّدة وبيانات ترخيص وفيزياء قابلة لإعادة الاستخدام.',
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
                          'لا توجد نماذج محزّمة بعد',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'الفهرس جاهز ويعرض فقط الملفات الموجودة فعلياً. ستضاف حزم CC0 بعد التحقق من الملفات وتراخيصها.',
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
                                  Text(asset.object.displayName,
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
                          ],
                        ),
                      )),
              ],
            );
          },
        ),
      );
}
