import 'package:flutter/material.dart';
import '../hand/hand_mirror_screen.dart';
import '../perception/scene_analysis_screen.dart';
import '../reconstruction/gaussian_splat_screen.dart';
import 'ar_scene_screen.dart';

class StudioScreen extends StatelessWidget {
  const StudioScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('الاستوديو المكاني')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('اختر طريقة التفاعل', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('كل التجارب تتحكم في تمثيل رقمي فقط. الكوب أو القلم أو أي جسم حقيقي يبقى كما هو.', style: TextStyle(color: Color(0xFF91A7BC), height: 1.6)),
        const SizedBox(height: 22),
        _StudioAction(
          icon: Icons.view_in_ar_rounded,
          title: 'الواقع المعزز المكاني',
          subtitle: 'امسح الأسطح وثبّت مجسمات ثلاثية الأبعاد داخل الغرفة.',
          tag: 'ARCore / ARKit',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ArSceneScreen())),
        ),
        _StudioAction(
          icon: Icons.back_hand_rounded,
          title: 'مرآة اليد الرقمية',
          subtitle: 'امسك الأصل الرقمي بإيماءة القرص وحرّكه دون لمس الجسم الحقيقي.',
          tag: 'MediaPipe Hand Landmarker',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HandMirrorScreen())),
        ),
        _StudioAction(
          icon: Icons.blur_on_rounded,
          title: 'إعادة بناء المشاهد ثلاثية الأبعاد',
          subtitle: 'اعرض عوالم Gaussian Splat المستوردة بصيغة SPZ أو LODSPLAT على GPU.',
          tag: 'SplatKit / Vulkan · Android arm64',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GaussianSplatScreen())),
        ),
        _StudioAction(
          icon: Icons.center_focus_strong_rounded,
          title: 'فهم المشهد والعزل',
          subtitle: 'التقط صورة لاكتشاف الأجسام وإنشاء قناع تقسيم محلي.',
          tag: 'Object Detector / Image Segmenter',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SceneAnalysisScreen())),
        ),
        const SizedBox(height: 14),
        const _CapabilityNote(),
      ],
    ),
  );
}

class _StudioAction extends StatelessWidget {
  const _StudioAction({required this.icon, required this.title, required this.subtitle, required this.tag, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final String tag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 14),
    color: const Color(0xFF111B2A),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(color: const Color(0xFF1B3441), borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, color: const Color(0xFF55E3D4), size: 27),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            Text(subtitle, style: const TextStyle(color: Color(0xFF91A7BC), fontSize: 12, height: 1.5)),
            const SizedBox(height: 8),
            Text(tag, style: const TextStyle(color: Color(0xFF62DCCE), fontSize: 10, letterSpacing: .4)),
          ])),
          const Icon(Icons.chevron_right, color: Color(0xFF71869A)),
        ]),
      ),
    ),
  );
}

class _CapabilityNote extends StatelessWidget {
  const _CapabilityNote();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(color: const Color(0xFF172536), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF29465B))),
    child: const Text(
      'ملاحظة: وضع AR يحتاج هاتفاً يدعم ARCore وخدمات Google Play للواقع المعزز. وضع اليد يستخدم الكاميرا بصورة مستقلة؛ لا نشغّل جلستي كاميرا متعارضتين في الوقت نفسه.',
      style: TextStyle(color: Color(0xFFA9BED0), fontSize: 12, height: 1.6),
    ),
  );
}
