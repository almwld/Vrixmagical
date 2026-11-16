import 'package:material_ui/material_ui.dart';
import '../../app/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('الإعدادات')),
    body: ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.secondary],
                  ),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: const Icon(
                  Icons.all_inclusive_rounded,
                  color: Color(0xFF07131D),
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'VirxMagical',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Digital Reality Engine',
                      style: TextStyle(color: AppColors.muted, fontSize: 10),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'الإصدار 0.2.0',
                      style: TextStyle(color: AppColors.primary, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        const _SettingsHeading(title: 'التفضيلات'),
        const SizedBox(height: 10),
        const _SettingsTile(
          icon: Icons.language_rounded,
          title: 'لغة التطبيق',
          value: 'العربية',
        ),
        const _SettingsTile(
          icon: Icons.palette_outlined,
          title: 'المظهر',
          value: 'داكن — واجهة مكانية',
        ),
        const SizedBox(height: 22),
        const _SettingsHeading(title: 'الخصوصية والمعالجة'),
        const SizedBox(height: 10),
        const _SettingsTile(
          icon: Icons.memory_rounded,
          title: 'معالجة الذكاء الاصطناعي',
          value: 'محلياً على الجهاز حيثما تدعم الوحدة ذلك',
        ),
        const _SettingsTile(
          icon: Icons.shield_outlined,
          title: 'الخصوصية',
          value: 'لا ترفع الصور تلقائياً إلى خادم',
        ),
        const SizedBox(height: 22),
        const _SettingsHeading(title: 'الجهاز والتطبيق'),
        const SizedBox(height: 10),
        const _SettingsTile(
          icon: Icons.devices_other_rounded,
          title: 'توافق الجهاز',
          value: 'يتم تحديد المتطلبات عند تشغيل كل وحدة',
        ),
        const _SettingsTile(
          icon: Icons.info_outline_rounded,
          title: 'حول التطبيق',
          value: 'منصة لبناء تجارب الواقع الرقمي',
        ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(
            children: [
              Icon(Icons.science_outlined, color: AppColors.secondary, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'بعض إعدادات النظام المتقدمة ستظهر عند اكتمال وحدات المحرك المرتبطة بها.',
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

class _SettingsHeading extends StatelessWidget {
  const _SettingsHeading({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: const TextStyle(
      color: AppColors.primary,
      fontSize: 12,
      fontWeight: FontWeight.w900,
    ),
  );
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 9),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 21),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
            ],
          ),
        ),
        const Icon(Icons.chevron_left_rounded, color: AppColors.muted, size: 19),
      ],
    ),
  );
}
