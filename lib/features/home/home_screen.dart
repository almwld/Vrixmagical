import 'package:material_ui/material_ui.dart';
import '../studio/studio_screen.dart';
import '../library/object_library_screen.dart';
import '../settings/settings_screen.dart';
import '../../app/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int index = 0;

  static const pages = [
    _OverviewTab(),
    StudioScreen(),
    ObjectLibraryScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: IndexedStack(index: index, children: pages)),
    bottomNavigationBar: NavigationBar(
      selectedIndex: index,
      onDestinationSelected: (value) => setState(() => index = value),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.space_dashboard_outlined),
          selectedIcon: Icon(Icons.space_dashboard_rounded),
          label: 'الرئيسية',
        ),
        NavigationDestination(
          icon: Icon(Icons.view_in_ar_outlined),
          selectedIcon: Icon(Icons.view_in_ar_rounded),
          label: 'الاستوديو',
        ),
        NavigationDestination(
          icon: Icon(Icons.category_outlined),
          selectedIcon: Icon(Icons.category_rounded),
          label: 'المكتبة',
        ),
        NavigationDestination(
          icon: Icon(Icons.tune_rounded),
          label: 'الإعدادات',
        ),
      ],
    ),
  );
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab();

  @override
  Widget build(BuildContext context) => CustomScrollView(
    physics: const BouncingScrollPhysics(),
    slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
        sliver: SliverList(
          delegate: SliverChildListDelegate([
            const _TopBar(),
            const SizedBox(height: 30),
            const Text(
              'اصنع واقعك\nبطريقتك.',
              style: TextStyle(
                fontSize: 35,
                height: 1.13,
                letterSpacing: -.8,
                fontWeight: FontWeight.w900,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'حوّل ما تراه حولك إلى مساحة رقمية يمكنك تشكيلها والتفاعل معها.',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 14,
                height: 1.7,
              ),
            ),
            const SizedBox(height: 24),
            _LaunchCard(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StudioScreen()),
              ),
            ),
            const SizedBox(height: 28),
            const _SectionHeading(
              title: 'أدواتك الإبداعية',
              subtitle: 'ابدأ من إحدى وحدات المحرك',
            ),
            const SizedBox(height: 14),
            _FeatureGrid(
              onOpenStudio: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StudioScreen()),
              ),
            ),
            const SizedBox(height: 28),
            const _SectionHeading(
              title: 'كيف يعمل VirxMagical؟',
              subtitle: 'من العالم الحقيقي إلى نسخة رقمية تفاعلية',
            ),
            const SizedBox(height: 14),
            const _WorkflowCard(),
            const SizedBox(height: 22),
            const _PrivacyStrip(),
          ]),
        ),
      ),
    ],
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, AppColors.secondary],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: .16),
              blurRadius: 22,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: const Icon(
          Icons.all_inclusive_rounded,
          color: Color(0xFF07131D),
          size: 29,
        ),
      ),
      const SizedBox(width: 12),
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'VirxMagical',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 2),
            Text(
              'DIGITAL REALITY ENGINE',
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 1.65,
                color: AppColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: const Icon(
          Icons.notifications_none_rounded,
          color: AppColors.muted,
          size: 21,
        ),
      ),
    ],
  );
}

class _LaunchCard extends StatelessWidget {
  const _LaunchCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(26),
      child: Ink(
        padding: const EdgeInsets.all(21),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF153A45), Color(0xFF17253C), Color(0xFF111A2A)],
          ),
          border: Border.all(color: AppColors.primary.withValues(alpha: .28)),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -8,
              top: 2,
              child: Icon(
                Icons.blur_on_rounded,
                size: 116,
                color: AppColors.primary.withValues(alpha: .09),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.radar_rounded,
                      color: AppColors.primary,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'SPATIAL STUDIO',
                      style: TextStyle(
                        color: AppColors.primary,
                        letterSpacing: 1.6,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: const Text(
                        'جاهز للتجربة',
                        style: TextStyle(
                          color: AppColors.success,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                const Text(
                  'ادخل إلى الاستوديو',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 7),
                const Text(
                  'امسح محيطك، اكتشف الأجسام، وابدأ ببناء تجربتك المكانية.',
                  style: TextStyle(
                    color: Color(0xFFB2C3D6),
                    height: 1.6,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'ابدأ الآن',
                        style: TextStyle(
                          color: Color(0xFF06151C),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(width: 10),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: Color(0xFF06151C),
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 4),
      Text(
        subtitle,
        style: const TextStyle(color: AppColors.muted, fontSize: 11),
      ),
    ],
  );
}

class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid({required this.onOpenStudio});

  final VoidCallback onOpenStudio;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = (constraints.maxWidth - 12) / 2;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _FeatureTile(
            width: width,
            icon: Icons.view_in_ar_rounded,
            title: 'الواقع المعزز',
            caption: 'مجسمات داخل محيطك',
            onTap: onOpenStudio,
          ),
          _FeatureTile(
            width: width,
            icon: Icons.back_hand_rounded,
            title: 'تتبع اليد',
            caption: 'تحكم بالإيماءات',
            onTap: onOpenStudio,
          ),
          _FeatureTile(
            width: width,
            icon: Icons.content_cut_rounded,
            title: 'العزل الذكي',
            caption: 'حدد العنصر بدقة',
            onTap: onOpenStudio,
          ),
          _FeatureTile(
            width: width,
            icon: Icons.blur_on_rounded,
            title: 'مشاهد ثلاثية',
            caption: 'استعرض ملفات Splat',
            onTap: onOpenStudio,
          ),
        ],
      );
    },
  );
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.width,
    required this.icon,
    required this.title,
    required this.caption,
    required this.onTap,
  });

  final double width;
  final IconData icon;
  final String title;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.primary, size: 22),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                caption,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _WorkflowCard extends StatelessWidget {
  const _WorkflowCard();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(21),
      border: Border.all(color: AppColors.border),
    ),
    child: const Column(
      children: [
        _WorkflowStep(
          number: '01',
          icon: Icons.camera_alt_outlined,
          title: 'التقط العالم',
          subtitle: 'استخدم الكاميرا لفهم المساحة والعناصر.',
        ),
        _WorkflowLine(),
        _WorkflowStep(
          number: '02',
          icon: Icons.auto_awesome_outlined,
          title: 'أنشئ التمثيل الرقمي',
          subtitle: 'حوّل العنصر إلى أصل رقمي قابل للتفاعل.',
        ),
        _WorkflowLine(),
        _WorkflowStep(
          number: '03',
          icon: Icons.touch_app_outlined,
          title: 'تفاعل وتحكّم',
          subtitle: 'حرّك الأصول الرقمية بإيماءاتك.',
        ),
      ],
    ),
  );
}

class _WorkflowStep extends StatelessWidget {
  const _WorkflowStep({
    required this.number,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final String number;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        number,
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(width: 13),
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 19, color: AppColors.primary),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: const TextStyle(color: AppColors.muted, fontSize: 10),
            ),
          ],
        ),
      ),
    ],
  );
}

class _WorkflowLine extends StatelessWidget {
  const _WorkflowLine();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(left: 25, top: 5, bottom: 5),
    child: Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        height: 15,
        child: VerticalDivider(color: AppColors.border, thickness: 1),
      ),
    ),
  );
}

class _PrivacyStrip extends StatelessWidget {
  const _PrivacyStrip();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surfaceElevated.withValues(alpha: .65),
      borderRadius: BorderRadius.circular(16),
    ),
    child: const Row(
      children: [
        Icon(Icons.shield_outlined, color: AppColors.success, size: 21),
        SizedBox(width: 11),
        Expanded(
          child: Text(
            'خصوصيتك أولاً — تتم معالجة الرؤية على الجهاز حيثما تدعم الوحدة ذلك.',
            style: TextStyle(color: AppColors.muted, fontSize: 10, height: 1.5),
          ),
        ),
      ],
    ),
  );
}
