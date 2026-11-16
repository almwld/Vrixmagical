import 'dart:async';

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
import 'package:material_ui/material_ui.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4, Vector3;

import '../../app/app_theme.dart';
import '../../services/physics_scene_service.dart';

class _PlacedAsset {
  const _PlacedAsset({
    required this.anchor,
    required this.node,
    required this.anchorWorldTransform,
    required this.bodyId,
    required this.floorBodyId,
  });

  final ARPlaneAnchor anchor;
  final ARNode node;
  final Matrix4 anchorWorldTransform;
  final String bodyId;
  final String floorBodyId;
}

class ArSceneScreen extends StatefulWidget {
  const ArSceneScreen({super.key});

  @override
  State<ArSceneScreen> createState() => _ArSceneScreenState();
}

class _ArSceneScreenState extends State<ArSceneScreen>
    with WidgetsBindingObserver {
  ARSessionManager? _session;
  ARObjectManager? _objects;
  ARAnchorManager? _anchors;
  PhysicsSceneService? _physics;
  Timer? _physicsTimer;
  DateTime? _lastPhysicsFrame;
  final List<_PlacedAsset> _placed = [];
  final Set<String> _manuallyControlledNodes = <String>{};
  String _status = 'بانتظار تهيئة الواقع المعزز…';
  bool _busy = false;
  bool _physicsFaultReported = false;

  static const _sampleModel =
      'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models/Duck/glTF-Binary/Duck.glb';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPhysicsTicker();
    } else {
      _stopPhysicsTicker();
      _physics?.resetAccumulator();
    }
  }

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
      if (mounted) setState(() => _status = 'تم اكتشاف $count سطحاً');
    };
    session.onError = (error) {
      if (mounted) setState(() => _status = 'خطأ AR: $error');
    };
    objects.onError = (error) {
      if (mounted) setState(() => _status = 'خطأ المجسم: $error');
    };
    anchors.onError = (error) {
      if (mounted) setState(() => _status = 'خطأ التثبيت: $error');
    };
    objects.onPanStart = _onNodeInteractionStart;
    objects.onRotationStart = _onNodeInteractionStart;
    objects.onPanEnd = _onNodeInteractionEnd;
    objects.onRotationEnd = _onNodeInteractionEnd;

    session.onInitialize(
      showPlanes: true,
      showFeaturePoints: false,
      handleTaps: true,
      handlePans: true,
      handleRotation: true,
    );
    objects.onInitialize();

    try {
      _physics = PhysicsSceneService();
      _startPhysicsTicker();
      if (mounted) {
        setState(() {
          _status = 'AR جاهز · محرك الفيزياء: ${_physics!.engineLabel}';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _status = 'AR جاهز · الفيزياء غير متاحة: $error');
      }
    }
  }

  void _startPhysicsTicker() {
    if (_physics == null || _physicsTimer != null) return;
    _lastPhysicsFrame = DateTime.now();
    _physicsTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _advancePhysics(),
    );
  }

  void _stopPhysicsTicker() {
    _physicsTimer?.cancel();
    _physicsTimer = null;
    _lastPhysicsFrame = null;
  }

  void _advancePhysics() {
    final physics = _physics;
    if (physics == null || physics.isDisposed) return;
    final now = DateTime.now();
    final previous = _lastPhysicsFrame;
    _lastPhysicsFrame = now;
    if (previous == null) return;

    try {
      physics.advance(
        now.difference(previous).inMicroseconds / Duration.microsecondsPerSecond,
      );
      final activeTransforms = physics.activeBodyTransforms();
      for (final asset in _placed) {
        if (_manuallyControlledNodes.contains(asset.node.name)) continue;
        final worldTransform = activeTransforms[asset.bodyId];
        if (worldTransform == null) continue;
        final anchorInverse = Matrix4.copy(asset.anchorWorldTransform)..invert();
        final localTransform = anchorInverse..multiply(worldTransform);
        asset.node.transform = Matrix4.compose(
          localTransform.getTranslation(),
          Quaternion.fromRotation(localTransform.getRotation()),
          asset.node.scale,
        );
      }
    } catch (error) {
      _stopPhysicsTicker();
      if (!_physicsFaultReported && mounted) {
        _physicsFaultReported = true;
        setState(() => _status = 'توقفت محاكاة الفيزياء لحماية المشهد: $error');
      }
    }
  }

  void _onNodeInteractionStart(String nodeName) {
    _manuallyControlledNodes.add(nodeName);
  }

  void _onNodeInteractionEnd(String nodeName, Matrix4 localTransform) {
    _manuallyControlledNodes.remove(nodeName);
    final physics = _physics;
    if (physics == null || physics.isDisposed) return;
    for (final asset in _placed) {
      if (asset.node.name != nodeName) continue;
      final worldTransform = Matrix4.copy(asset.anchorWorldTransform)
        ..multiply(localTransform);
      physics.setBodyWorldTransform(asset.bodyId, worldTransform);
      physics.resetAccumulator();
      break;
    }
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
    final anchorTransform = Matrix4.copy(hit.worldTransform);
    final anchor = ARPlaneAnchor(transformation: hit.worldTransform);
    String? floorBodyId;
    String? dynamicBodyId;
    ARNode? createdNode;
    var anchorWasAdded = false;

    try {
      final anchored = await anchors.addAnchor(anchor);
      if (anchored != true) {
        if (mounted) setState(() => _status = 'تعذّر تثبيت الجسم على هذا السطح.');
        return;
      }
      anchorWasAdded = true;

      final node = ARNode(
        type: NodeType.webGLB,
        uri: _sampleModel,
        position: Vector3(0, 0.16, 0),
        scale: Vector3(0.12, 0.12, 0.12),
      );
      createdNode = node;
      final added = await objects.addNode(node, planeAnchor: anchor);
      if (added != true) {
        await anchors.removeAnchor(anchor);
        if (mounted) setState(() => _status = 'تعذّر تحميل النموذج ثلاثي الأبعاد.');
        return;
      }

      final physics = _physics;
      if (physics != null && !physics.isDisposed) {
        floorBodyId = 'floor_${node.name}';
        dynamicBodyId = 'body_${node.name}';

        final planeNormal = Vector3(
          anchorTransform[4],
          anchorTransform[5],
          anchorTransform[6],
        );
        if (planeNormal.length2 > 1e-8) {
          planeNormal.normalize();
        } else {
          planeNormal.setValues(0, 1, 0);
        }

        final floorTransform = Matrix4.copy(anchorTransform)
          ..setTranslation(
            anchorTransform.getTranslation() - planeNormal * 0.025,
          );
        final bodyTransform = Matrix4.copy(anchorTransform)
          ..setTranslation(
            anchorTransform.getTranslation() + planeNormal * 0.16,
          );

        physics.addStaticBox(
          id: floorBodyId,
          worldTransform: floorTransform,
          halfExtents: Vector3(2, 0.025, 2),
          friction: 0.9,
        );
        physics.addDynamicBox(
          id: dynamicBodyId,
          worldTransform: bodyTransform,
          halfExtents: Vector3(0.07, 0.06, 0.09),
          friction: 0.65,
          restitution: 0.08,
        );
      }

      if (!mounted) return;
      setState(() {
        _placed.add(
          _PlacedAsset(
            anchor: anchor,
            node: node,
            anchorWorldTransform: anchorTransform,
            bodyId: dynamicBodyId ?? '',
            floorBodyId: floorBodyId ?? '',
          ),
        );
        _status = physics == null
            ? 'تم تثبيت المجسم · محرك الفيزياء غير متاح.'
            : 'تم تثبيت المجسم · تصادم وجاذبية Jolt مفعّلان.';
      });
    } catch (error) {
      if (dynamicBodyId != null) _physics?.removeBody(dynamicBodyId);
      if (floorBodyId != null) _physics?.removeBody(floorBodyId);
      if (createdNode != null) await objects.removeNode(createdNode);
      if (anchorWasAdded) await anchors.removeAnchor(anchor);
      if (mounted) setState(() => _status = 'فشلت عملية التثبيت: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeLast() async {
    if (_placed.isEmpty) return;
    final asset = _placed.removeLast();
    _physics?.removeBody(asset.bodyId);
    _physics?.removeBody(asset.floorBodyId);
    _manuallyControlledNodes.remove(asset.node.name);
    await _objects?.removeNode(asset.node);
    await _anchors?.removeAnchor(asset.anchor);
    if (mounted) {
      setState(
        () => _status = 'تمت إزالة آخر أصل رقمي. المتبقي: ${_placed.length}',
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPhysicsTicker();
    _physics?.dispose();
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
