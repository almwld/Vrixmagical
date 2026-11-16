import 'package:material_ui/material_ui.dart';

import '../../app/app_theme.dart';
import 'package:flutter_reality/ar_flutter_plugin.dart';
import 'package:flutter_reality/datatypes/config_planedetection.dart';
import 'package:flutter_reality/datatypes/node_types.dart';
import 'package:flutter_reality/managers/ar_anchor_manager.dart';
import 'package:flutter_reality/managers/ar_location_manager.dart';
import 'package:flutter_reality/managers/ar_object_manager.dart';
import 'package:flutter_reality/managers/ar_session_manager.dart';
import 'package:flutter_reality/models/ar_anchor.dart';
import 'package:flutter_reality/models/ar_hittest_result.dart';
import 'package:flutter_reality/models/ar_node.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

class _PlacedAsset {
  const _PlacedAsset(this.anchor, this.node);
  final ARPlaneAnchor anchor;
  final ARNode node;
}

class ArSceneScreen extends StatefulWidget {
  const ArSceneScreen({super.key});
  @override
  State<ArSceneScreen> createState() => _ArSceneScreenState();
}

class _ArSceneScreenState extends State<ArSceneScreen> {
  ARSessionManager? _session;
  ARObjectManager? _objects;
  ARAnchorManager? _anchors;
  final List<_PlacedAsset> _placed = [];
  String _status = 'بانتظار تهيئة الواقع المعزز…';
  bool _busy = false;

  static const _sampleModel = 'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models/Duck/glTF-Binary/Duck.glb';

  void _onCreated(
    ARSessionManager session,
    ARObjectManager objects,
    ARAnchorManager anchors,
    ARLocationManager locations,
  ) {
    _session = session;
    _objects = objects;
    _anchors = anchors;
    session.onPlaneOrPointTap = _onSurfaceTap;
    session.onPlaneDetected = (count) {
      if (mounted) setState(() => _status = 'تم اكتشاف ' + count.toString() + ' سطحاً');
    };
    session.onError = (error) {
      if (mounted) setState(() => _status = 'خطأ AR: ' + error.toString());
    };
    objects.onError = (error) {
      if (mounted) setState(() => _status = 'خطأ المجسم: ' + error.toString());
    };
    anchors.onError = (error) {
      if (mounted) setState(() => _status = 'خطأ التثبيت: ' + error.toString());
    };
    session.onInitialize(
      showPlanes: true,
      showFeaturePoints: false,
      handleTaps: true,
      handlePans: true,
      handleRotation: true,
    );
    objects.onInitialize();
    if (mounted) setState(() => _status = 'حرّك الهاتف ببطء لمسح سطح ثم المسه.');
  }

  Future<void> _onSurfaceTap(List<ARHitTestResult> hits) async {
    if (_busy || hits.isEmpty) return;
    final hit = hits.first;
    final anchors = _anchors;
    final objects = _objects;
    if (anchors == null || objects == null) return;

    setState(() {
      _busy = true;
      _status = 'جارٍ تثبيت الأصل الرقمي…';
    });
    final anchor = ARPlaneAnchor(transformation: hit.worldTransform);
    try {
      final anchored = await anchors.addAnchor(anchor);
      if (anchored != true) {
        if (mounted) setState(() => _status = 'تعذّر تثبيت الجسم على هذا السطح.');
        return;
      }
      final node = ARNode(
        type: NodeType.webGLB,
        uri: _sampleModel,
        scale: Vector3(0.12, 0.12, 0.12),
      );
      final added = await objects.addNode(node, planeAnchor: anchor);
      if (added != true) {
        await anchors.removeAnchor(anchor);
        if (mounted) setState(() => _status = 'تعذّر تحميل النموذج ثلاثي الأبعاد.');
        return;
      }
      if (!mounted) return;
      setState(() {
        _placed.add(_PlacedAsset(anchor, node));
        _status = 'تم تثبيت مجسم رقمي. يمكنك سحبه وتدويره.';
      });
    } catch (error) {
      if (mounted) setState(() => _status = 'فشلت عملية التثبيت: ' + error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeLast() async {
    if (_placed.isEmpty) return;
    final asset = _placed.removeLast();
    await _objects?.removeNode(asset.node);
    await _anchors?.removeAnchor(asset.anchor);
    if (mounted) setState(() => _status = 'تمت إزالة آخر أصل رقمي. المتبقي: ' + _placed.length.toString());
  }

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('الواقع المعزز'),
      actions: [
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 16),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Row(
                children: [
                  Icon(Icons.circle, color: AppColors.success, size: 6),
                  SizedBox(width: 6),
                  Text(
                    'AR SESSION',
                    style: TextStyle(
                      color: AppColors.success,
                      fontSize: 8,
                      letterSpacing: .8,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
    body: Stack(
      children: [
        ARView(
          showPlatformType: false,
          planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical,
          onARViewCreated: _onCreated,
        ),
        Positioned(
          top: 16,
          left: 14,
          right: 14,
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: const Color(0xE6101A28),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.radar_rounded, color: AppColors.primary, size: 21),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _status,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 11,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 14,
          right: 14,
          bottom: 16,
          child: SafeArea(
            child: Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: const Color(0xEE101A28),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.primary.withValues(alpha: .25)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.view_in_ar_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 9),
                      const Expanded(
                        child: Text(
                          'الأصول المثبّتة',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text(
                        _placed.length.toString().padLeft(2, '0'),
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 11),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _busy || _placed.isEmpty ? null : _removeLast,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('إزالة آخر مجسم'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'المجسمات رقمية ولا تغيّر الأجسام الحقيقية.',
                    style: TextStyle(color: AppColors.muted, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
