import 'package:flutter/material.dart';
import '../../services/ar_capability_service.dart';

class StudioScreen extends StatefulWidget {
  const StudioScreen({super.key});
  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen> {
  final capabilities = ArCapabilityService();
  bool cameraGranted = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('الاستوديو المكاني')),
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF101A29),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0xFF2B4559)),
            ),
            child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.view_in_ar_rounded, size: 68, color: Color(0xFF4CE3D4)),
              SizedBox(height: 18),
              Text('مساحة المعاينة ثلاثية الأبعاد', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              SizedBox(height: 8),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 28),
                child: Text('سيتم هنا تشغيل بث الكاميرا وتتبع ARCore وإظهار الأجسام الرقمية المثبتة في البيئة.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF91A7BC), height: 1.6)),
              ),
              SizedBox(height: 20),
              Text('واجهة الاستوديو — بانتظار ربط محرك AR', style: TextStyle(color: Color(0xFF8CEADF), fontSize: 11)),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () async {
            final granted = await capabilities.requestCameraPermission();
            if (!mounted) return;
            setState(() => cameraGranted = granted);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(granted ? 'تم منح إذن الكاميرا' : 'لم يتم منح إذن الكاميرا')));
          },
          icon: const Icon(Icons.camera_alt_outlined),
          label: Text(cameraGranted ? 'إذن الكاميرا متاح' : 'تجهيز الكاميرا'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('سيتم تفعيل إنشاء الأجسام بعد دمج محرك AR والفيزياء.'))),
          icon: const Icon(Icons.add_box_outlined),
          label: const Text('إضافة جسم رقمي'),
        ),
      ]),
    ),
  );
}
