import 'package:flutter/material.dart';
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
    appBar: AppBar(title: const Text('الواقع المعزز')),
    body: Stack(children: [
      ARView(
        showPlatformType: false,
        planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical,
        onARViewCreated: _onCreated,
      ),
      Positioned(
        left: 14, right: 14, bottom: 18,
        child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Card(
            color: const Color(0xE6111B2A),
            child: Padding(padding: const EdgeInsets.all(12), child: Text(_status, textAlign: TextAlign.center)),
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy || _placed.isEmpty ? null : _removeLast,
              icon: const Icon(Icons.delete_outline),
              label: Text('إزالة آخر مجسم (' + _placed.length.toString() + ')'),
            ),
          ),
          const Text('الأجسام المعروضة رقمية فقط ولا تغيّر الأجسام الحقيقية.', style: TextStyle(color: Colors.white, fontSize: 11)),
        ])),
      ),
    ]),
  );
}
