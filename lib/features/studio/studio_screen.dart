import 'package:material_ui/material_ui.dart';
import '../../app/app_theme.dart';
import '../hand/hand_mirror_screen.dart';
import '../perception/scene_analysis_screen.dart';
import '../perception/interactive_cutout_screen.dart';
import '../reconstruction/gaussian_splat_screen.dart';
import 'ar_scene_screen.dart';

class StudioScreen extends StatelessWidget {
  const StudioScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('الاستوديو المكاني'),
      actions: [
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Text(
                'SPATIAL LAB',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 9,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
    body: ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
      children: [
        const Text(
          'اختر مساحة\nالتجربة التالية.',
          style: TextStyle(
            fontSize: 30,
            height: 1.2,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'أدوات الرؤية والإدراك المكاني والتحكم بالأصول الرقمية، في مساحة عمل واحدة.',
          style: TextStyle(color: AppColors.muted, height: 1.7, fontSize: 12),
        ),
        const SizedBox(height: 22),
        _StudioFeatured(
          onTap: () => _open(context, const ArSceneScreen()),
        ),
        const SizedBox(height: 26),
        const Row(
          children: [
            Text(
              'أدوات المحرك',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            Spacer(),
            Text(
              '5 وحدات',
              style: TextStyle(color: AppColors.muted, fontSize: 10),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _StudioTool(
          icon: Icons.back_hand_rounded,
          title: 'مرآة اليد الرقمية',
          description: 'تتبّع اليد والإيماءات للتحكم في العناصر الرقمية.',
          technology: 'MEDIAPIPE · HAND LANDMARKER',
          color: const Color(0xFF69D8C7),
          onTap: () => _open(context, const HandMirrorScreen()),
        ),
        _StudioTool(
          icon: Icons.content_cut_rounded,
          title: 'العزل التفاعلي الدقيق',
          description: 'المس العنصر لتحديده، وأضف نقاط استبعاد لتنقية القناع.',
          technology: 'INTERACTIVE SEGMENTER · MAGICTOUCH',
          color: const Color(0xFF9C9BFF),
          onTap: () => _open(context, const InteractiveCutoutScreen()),
        ),
        _StudioTool(
          icon: Icons.center_focus_strong_rounded,
          title: 'تحليل المشهد',
          description: 'اكتشاف الأجسام وإنشاء أقنعة تقسيم من الصور.',
          technology: 'OBJECT DETECTOR · IMAGE SEGMENTER',
          color: const Color(0xFF78B7FF),
          onTap: () => _open(context, const SceneAnalysisScreen()),
        ),
        _StudioTool(
          icon: Icons.blur_on_rounded,
          title: 'عارض المشاهد ثلاثية الأبعاد',
          description: 'استعرض ملفات Gaussian Splat المدعومة على GPU.',
          technology: 'SPLATKIT · VULKAN · ANDROID ARM64',
          color: const Color(0xFFFFC77A),
          onTap: () => _open(context, const GaussianSplatScreen()),
        ),
        const SizedBox(height: 16),
        const _StudioFootnote(),
      ],
    ),
  );

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

class _StudioFeatured extends StatelessWidget {
  const _StudioFeatured({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Ink(
        padding: const EdgeInsets.all(19),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1C4850), Color(0xFF1A2B43), Color(0xFF131D2D)],
          ),
          border: Border.all(color: AppColors.primary.withValues(alpha: .25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.view_in_ar_rounded, color: AppColors.primary),
                SizedBox(width: 8),
                Text(
                  'تجربة مكانية مباشرة',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Spacer(),
                Icon(Icons.north_east_rounded, color: AppColors.muted, size: 18),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'الواقع المعزز',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 7),
            const Text(
              'اكتشف الأسطح في محيطك وثبّت المجسمات ثلاثية الأبعاد في المشهد.',
              style: TextStyle(color: Color(0xFFB4C8D7), fontSize: 12, height: 1.6),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'فتح تجربة AR',
                style: TextStyle(
                  color: Color(0xFF07151D),
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _StudioTool extends StatelessWidget {
  const _StudioTool({
    required this.icon,
    required this.title,
    required this.description,
    required this.technology,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final String technology;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 11),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(19),
      border: Border.all(color: AppColors.border),
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 5),
                    Text(
                      description,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 10,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      technology,
                      style: TextStyle(
                        color: color,
                        fontSize: 8,
                        letterSpacing: .7,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    ),
  );
}

class _StudioFootnote extends StatelessWidget {
  const _StudioFootnote();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, color: AppColors.secondary, size: 18),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'تختلف متطلبات التشغيل حسب الوحدة. تحتاج تجربة AR إلى جهاز متوافق مع ARCore، بينما يتطلب عارض SplatKit جهاز Android بمعمارية arm64 ودعم Vulkan.',
            style: TextStyle(color: AppColors.muted, fontSize: 10, height: 1.6),
          ),
        ),
      ],
    ),
  );
}
