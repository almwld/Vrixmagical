import 'package:material_ui/material_ui.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('الإعدادات')),
    body: ListView(padding: const EdgeInsets.all(20), children: const [
      _SettingRow(icon: Icons.language, title: 'اللغة', value: 'العربية'),
      _SettingRow(icon: Icons.memory, title: 'معالجة الذكاء الاصطناعي', value: 'سيتم تحديدها لاحقاً'),
      _SettingRow(icon: Icons.privacy_tip_outlined, title: 'الخصوصية', value: 'المعالجة المحلية هي الخيار الافتراضي'),
      _SettingRow(icon: Icons.devices_other, title: 'قدرات الجهاز', value: 'سيتم فحص دعم ARCore'),
      _SettingRow(icon: Icons.info_outline, title: 'حول VirxMagical', value: 'Digital Reality Engine · 0.1.0'),
    ]),
  );
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.icon, required this.title, required this.value});
  final IconData icon;
  final String title;
  final String value;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 7),
    leading: Icon(icon, color: const Color(0xFF55E3D4)),
    title: Text(title),
    subtitle: Text(value, style: const TextStyle(color: Color(0xFF91A7BC))),
  );
}
