import 'package:flutter/material.dart';
import '../studio/studio_screen.dart';
import '../library/object_library_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int index = 0;
  static const pages = [_OverviewTab(), StudioScreen(), ObjectLibraryScreen(), SettingsScreen()];

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: pages[index]),
    bottomNavigationBar: NavigationBar(
      selectedIndex: index,
      onDestinationSelected: (value) => setState(() => index = value),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'الرئيسية'),
        NavigationDestination(icon: Icon(Icons.view_in_ar_outlined), selectedIcon: Icon(Icons.view_in_ar), label: 'الاستوديو'),
        NavigationDestination(icon: Icon(Icons.category_outlined), selectedIcon: Icon(Icons.category), label: 'الأجسام'),
        NavigationDestination(icon: Icon(Icons.tune), label: 'الإعدادات'),
      ],
    ),
  );
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab();

  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        sliver: SliverToBoxAdapter(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  gradient: const LinearGradient(colors: [Color(0xFF42E8D5), Color(0xFF3977FF)]),
                ),
                child: const Icon(Icons.blur_on_rounded, color: Color(0xFF07111C), size: 29),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('VirxMagical', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
                Text('DIGITAL REALITY ENGINE', style: TextStyle(fontSize: 10, letterSpacing: 2, color: Color(0xFF8FA4B9))),
              ])),
              const Icon(Icons.notifications_none_rounded, color: Color(0xFF9EB2C7)),
            ]),
            const SizedBox(height: 28),
            const Text('حوّل العالم من حولك إلى مساحة رقمية تفاعلية', style: TextStyle(fontSize: 24, height: 1.35, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('أنشئ أجساماً رقمية، ثبّتها في المكان، وتفاعل معها عبر الكاميرا واليد.', style: TextStyle(color: Color(0xFF9BAFC3), height: 1.6)),
            const SizedBox(height: 22),
            _HeroCard(onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StudioScreen()))),
            const SizedBox(height: 26),
            const Text('وحدات المحرك', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            const Wrap(spacing: 10, runSpacing: 10, children: [
              _ModuleChip(icon: Icons.camera_alt_outlined, label: 'الرؤية والكاميرا', status: 'قيد الدمج'),
              _ModuleChip(icon: Icons.back_hand_outlined, label: 'تتبع اليد', status: 'قيد الدمج'),
              _ModuleChip(icon: Icons.view_in_ar, label: 'العمق و AR', status: 'قيد الدمج'),
              _ModuleChip(icon: Icons.bubble_chart_outlined, label: 'الفيزياء', status: 'قيد الدمج'),
              _ModuleChip(icon: Icons.wb_sunny_outlined, label: 'الإضاءة', status: 'مخطط'),
              _ModuleChip(icon: Icons.auto_awesome, label: 'الذكاء الاصطناعي', status: 'مخطط'),
            ]),
          ]),
        ),
      ),
    ],
  );
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(24),
    child: Ink(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF173B49), Color(0xFF17213D), Color(0xFF111827)]),
        border: Border.all(color: const Color(0xFF3DDCCB).withOpacity(.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.center_focus_strong, color: Color(0xFF51E8D8)),
          SizedBox(width: 8),
          Text('LIVE SPATIAL STUDIO', style: TextStyle(fontSize: 11, letterSpacing: 1.6, color: Color(0xFF9DEFE6), fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 24),
        const Text('ابدأ تجربة الواقع الرقمي', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('افتح الكاميرا واستعد لإضافة أول جسم افتراضي إلى بيئتك.', style: TextStyle(color: Color(0xFFB2C5D7), height: 1.5)),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(color: const Color(0xFF49E4D3), borderRadius: BorderRadius.circular(14)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Text('فتح الاستوديو', style: TextStyle(color: Color(0xFF07151D), fontWeight: FontWeight.w800)),
            SizedBox(width: 8),
            Icon(Icons.arrow_forward_rounded, color: Color(0xFF07151D), size: 18),
          ]),
        ),
      ]),
    ),
  );
}

class _ModuleChip extends StatelessWidget {
  const _ModuleChip({required this.icon, required this.label, required this.status});
  final IconData icon;
  final String label;
  final String status;
  @override
  Widget build(BuildContext context) => Container(
    width: 158,
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(color: const Color(0xFF111B2A), borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xFF26374B))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: const Color(0xFF55E3D4)),
      const SizedBox(height: 12),
      Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(status, style: const TextStyle(fontSize: 10, color: Color(0xFF8DA3B9))),
    ]),
  );
}
