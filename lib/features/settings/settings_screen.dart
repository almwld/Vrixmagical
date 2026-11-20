import 'package:material_ui/material_ui.dart';
import '../../app/app_theme.dart';

enum _SettingsGroup { interface, engine, interaction, device, privacy }

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إعدادات المحرك')),
    body: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 28), children: [
      Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF173A45), AppColors.surface]),
        borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.primary.withValues(alpha: .25))),
        child: const Row(children: [Icon(Icons.tune_rounded, color: AppColors.primary, size: 30), SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('لوحة تحكم VRIX', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            SizedBox(height: 4), Text('تحكم في الواجهة والمحرك والتفاعل والجهاز.', style: TextStyle(color: AppColors.muted, fontSize: 11)),
          ]))])),
      const SizedBox(height: 20),
      _group(context, 'الواجهة والعرض', Icons.language_rounded, _SettingsGroup.interface, 'اتجاه RTL، اللغة، المظهر، وحجم النص.'),
      _group(context, 'إعدادات المحرك', Icons.view_in_ar_rounded, _SettingsGroup.engine, 'جودة العرض، المجسمات، الخامات، والتصدير.'),
      _group(context, 'التفاعل والسلوك', Icons.back_hand_rounded, _SettingsGroup.interaction, 'تتبع اليد، الحركة العضوية، والفيزياء.'),
      _group(context, 'الجهاز والشاشة', Icons.devices_rounded, _SettingsGroup.device, 'توافق ARCore وشاشة LG Wing المزدوجة.'),
      _group(context, 'الخصوصية والتخزين', Icons.shield_outlined, _SettingsGroup.privacy, 'مكان معالجة البيانات وإدارة ملفات المجسمات.'),
      const SizedBox(height: 16),
      const Text('الإصدار 0.2.0 · Digital Reality Engine', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 10)),
    ]),
  );
  Widget _group(BuildContext context, String title, IconData icon, _SettingsGroup group, String subtitle) => Card(
    child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
      leading: Icon(icon, color: AppColors.primary, size: 24),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
      subtitle: Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
      trailing: const Icon(Icons.chevron_left_rounded),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _SettingsDetailScreen(group: group, title: title))),
    ),
  );
}

class _SettingsDetailScreen extends StatefulWidget {
  const _SettingsDetailScreen({required this.group, required this.title});
  final _SettingsGroup group; final String title;
  @override
  State<_SettingsDetailScreen> createState() => _SettingsDetailScreenState();
}
class _SettingsDetailScreenState extends State<_SettingsDetailScreen> {
  final Map<String, bool> _switches = {'rtl':true,'animations':true,'showNames':true,'pbr':true,'hand':false,'physics':true,'breathing':true,'gaze':true,'wing':true,'saveLocal':true,'analytics':false};
  double _quality=.75, _touch=.18;
  Widget _toggle(String key,String title,String description) => SwitchListTile(
    value:_switches[key]??false,onChanged:(v)=>setState(()=>_switches[key]=v),
    title:Text(title,style:const TextStyle(fontWeight:FontWeight.w800,fontSize:12)),
    subtitle:Text(description,style:const TextStyle(color:AppColors.muted,fontSize:10)),activeThumbColor:AppColors.primary);
  Widget _slider(String title,double value,ValueChanged<double> onChanged) => Card(child:Padding(padding:const EdgeInsets.all(15),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text(title,style:const TextStyle(fontWeight:FontWeight.w800,fontSize:12)),Slider(value:value,onChanged:onChanged),
    Text('${(value*100).round()}%',style:const TextStyle(color:AppColors.primary,fontSize:11)),
  ])));
  @override
  Widget build(BuildContext context) {
    final children=<Widget>[];
    switch(widget.group) {
      case _SettingsGroup.interface:
        children.addAll([_toggle('rtl','واجهة عربية من اليمين إلى اليسار','تطبيق اتجاه RTL على صفحات Material والنصوص والأزرار.'),_toggle('animations','انتقالات الواجهة','تفعيل انتقالات الصفحات والحركات غير المرتبطة بالمحاكاة.'),const ListTile(title:Text('لغة الواجهة'),subtitle:Text('العربية — اتجاه RTL مفعل افتراضياً')),const ListTile(title:Text('المظهر'),subtitle:Text('داكن مكاني · تركواز وأزرق'))]); break;
      case _SettingsGroup.engine:
        children.addAll([_toggle('showNames','إظهار التسميات العربية','عرض أسماء الأصول والتسميات الدلالية بالعربية حيث تتوفر بياناتها.'),_toggle('pbr','خامات PBR والإضاءة','استخدام خامات GLB المضمنة كما يدعمها عارض المحرك.'),_slider('ميزانية جودة العرض',_quality,(v)=>setState(()=>_quality=v)),const ListTile(title:Text('تنسيقات الاستيراد'),subtitle:Text('GLB / GLTF')),const ListTile(title:Text('تصدير المشهد'),subtitle:Text('تصدير GLB من وحدات إعادة البناء عند توفر ملف صالح.'))]); break;
      case _SettingsGroup.interaction:
        children.addAll([_toggle('hand','تتبع اليد','يتطلب حجز جلسة الكاميرا وعدم تشغيل مرآة اليد بالتزامن مع ARCore.'),_toggle('breathing','التنفس والحركة الدقيقة','يتطلب شخصية ذات هيكل عظمي مدعوم من العارض.'),_toggle('gaze','تتبع النظر والرأس','يتطلب Rig وبيانات عظام وواجهة تحريك مدعومة.'),_toggle('physics','محاكاة Jolt وXPBD','تفعيل محاكاة الأجسام الصلبة واللينة.'),_slider('عتبة قرب التلامس',_touch,(v)=>setState(()=>_touch=v))]); break;
      case _SettingsGroup.device:
        children.addAll([_toggle('wing','لوحة LG Wing الثانوية','إظهار لوحة التحكم على الشاشة الثانية عند توفرها.'),const ListTile(title:Text('الواقع المعزز'),subtitle:Text('ARCore · تتحدد الإمكانات حسب الجهاز.')),const ListTile(title:Text('المعمارية'),subtitle:Text('تُنتج CI ملفات APK منفصلة لكل ABI مدعوم.'))]); break;
      case _SettingsGroup.privacy:
        children.addAll([_toggle('saveLocal','حفظ النماذج محلياً','تخزين مكتبة الأصول في مساحة التطبيق الخاصة.'),_toggle('analytics','إحصاءات تشخيصية اختيارية','متوقفة افتراضياً؛ لا تُرسل صور الكاميرا.'),const ListTile(title:Text('أذونات الكاميرا'),subtitle:Text('تستخدم عند تشغيل AR أو أدوات الرؤية فقط.')),const ListTile(title:Text('ملفات GLB'),subtitle:Text('تظل في مساحة التطبيق حتى تصديرها أو حذفها من المكتبة.'))]); break;
    }
    return Scaffold(appBar:AppBar(title:Text(widget.title)),body:ListView(padding:const EdgeInsets.all(14),children:[
      ...children,const SizedBox(height:16),
      const Text('ملاحظة: عناصر التحكم التي تتطلب دعماً من محرك العرض أو خدمة النظام لن تُفعّل سلوكاً غير متوفر.',style:TextStyle(color:AppColors.muted,fontSize:10,height:1.6)),
    ]));
  }
}
