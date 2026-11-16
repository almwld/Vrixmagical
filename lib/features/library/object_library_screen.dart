import 'package:material_ui/material_ui.dart';

class ObjectLibraryScreen extends StatelessWidget {
  const ObjectLibraryScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('مكتبة الأجسام الرقمية')),
    body: ListView(padding: const EdgeInsets.all(20), children: const [
      Text('أصول جاهزة للتجربة', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
      SizedBox(height: 8),
      Text('ستدعم المكتبة استيراد GLB وGLTF وإدارة الأجسام والمشاهد المحفوظة.', style: TextStyle(color: Color(0xFF91A7BC), height: 1.6)),
      SizedBox(height: 20),
      _AssetTile(icon: Icons.sports_baseball_outlined, title: 'أجسام فيزيائية', subtitle: 'كرات ومكعبات وأشكال قابلة للتصادم'),
      _AssetTile(icon: Icons.water_drop_outlined, title: 'سوائل ومواد', subtitle: 'سوائل رقمية ومواد مرنة — مرحلة لاحقة'),
      _AssetTile(icon: Icons.view_in_ar_outlined, title: 'نماذج ثلاثية الأبعاد', subtitle: 'استيراد GLB / GLTF'),
      _AssetTile(icon: Icons.blur_on, title: 'مشاهد Gaussian Splat', subtitle: 'عرض المشاهد المعاد بناؤها — مرحلة لاحقة'),
    ]),
  );
}

class _AssetTile extends StatelessWidget {
  const _AssetTile({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: const Color(0xFF111B2A), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFF26374B))),
    child: Row(children: [
      Container(width: 46, height: 46, decoration: BoxDecoration(color: const Color(0xFF1B3441), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: const Color(0xFF55E3D4))),
      const SizedBox(width: 13),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: Color(0xFF91A7BC), fontSize: 12)),
      ])),
      const Icon(Icons.chevron_right, color: Color(0xFF71869A)),
    ]),
  );
}
