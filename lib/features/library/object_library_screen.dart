import 'package:material_ui/material_ui.dart';
import '../../app/app_theme.dart';

class ObjectLibraryScreen extends StatelessWidget {
  const ObjectLibraryScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('مكتبة الأصول'),
      actions: [
        Padding(
          padding: const EdgeInsets.only(left: 18),
          child: Center(
            child: Icon(Icons.search_rounded, color: AppColors.muted),
          ),
        ),
      ],
    ),
    body: ListView(
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
            border: Border.all(color: AppColors.secondary.withValues(alpha: .22)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.inventory_2_outlined, color: AppColors.secondary, size: 27),
              SizedBox(height: 18),
              Text(
                'مساحة أصولك الرقمية',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 7),
              Text(
                'مكان موحّد لتنظيم النماذج والمشاهد التي تستخدمها في تجارب الواقع الرقمي.',
                style: TextStyle(color: Color(0xFFB5C5D8), fontSize: 11, height: 1.7),
              ),
            ],
          ),
        ),
        const SizedBox(height: 25),
        const Text(
          'فئات الأصول',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 5),
        const Text(
          'استكشف أنواع المحتوى التي يستهدف المحرك دعمها.',
          style: TextStyle(color: AppColors.muted, fontSize: 11),
        ),
        const SizedBox(height: 15),
        const _AssetCategory(
          icon: Icons.view_in_ar_rounded,
          title: 'النماذج ثلاثية الأبعاد',
          subtitle: 'أصول GLB و GLTF للمشاهد المكانية.',
          status: 'قيد التطوير',
          color: Color(0xFF69D8C7),
        ),
        const _AssetCategory(
          icon: Icons.blur_on_rounded,
          title: 'مشاهد Gaussian Splat',
          subtitle: 'ملفات SPZ و LODSPLAT للعرض المكاني.',
          status: 'عارض متاح',
          color: Color(0xFF9B9AFF),
        ),
        const _AssetCategory(
          icon: Icons.category_rounded,
          title: 'الأجسام التفاعلية',
          subtitle: 'مكتبة عناصر رقمية قابلة للتحريك والتفاعل.',
          status: 'قيد التطوير',
          color: Color(0xFFFFC77A),
        ),
        const _AssetCategory(
          icon: Icons.water_drop_outlined,
          title: 'المواد والمحاكاة',
          subtitle: 'مواد مرنة وسوائل ومؤثرات فيزيائية.',
          status: 'مخطط',
          color: Color(0xFF78B7FF),
        ),
        const SizedBox(height: 15),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: const Row(
            children: [
              Icon(Icons.tips_and_updates_outlined, color: AppColors.primary, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'المكتبة حالياً تعرض خارطة أنواع الأصول المستهدفة؛ إدارة الملفات والاستيراد المباشر ستضاف عند اكتمال مسار الأصول.',
                  style: TextStyle(color: AppColors.muted, fontSize: 10, height: 1.6),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _AssetCategory extends StatelessWidget {
  const _AssetCategory({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String status;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 11),
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color, size: 23),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(color: AppColors.muted, fontSize: 10, height: 1.5),
              ),
              const SizedBox(height: 8),
              Text(
                status,
                style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
