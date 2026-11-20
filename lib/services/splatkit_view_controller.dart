import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Per-PlatformView typed bridge to the native SplatKit/Vulkan renderer.
class SplatKitViewController extends ChangeNotifier {
  SplatKitViewController(int viewId)
      : _channel = MethodChannel('virxmagical/splat_view/$viewId');

  final MethodChannel _channel;
  Timer? _statsTimer;
  bool _disposed = false;
  bool _connected = false;

  bool get isConnected => _connected;
  bool gpuAvailable = false;
  bool worldReady = false;
  bool firstFrameReady = false;
  bool motionEnabled = false;
  String gpuDescription = '';
  String status = 'جارٍ الاتصال بمحرك Vulkan…';
  String? error;
  String quality = 'medium';
  bool hiZOcclusionEnabled = false;
  bool? renderPolicyAccepted;
  List<String> renderPolicyWarnings = const [];
  Map<String, dynamic> stats = const {};
  Map<String, dynamic> cameraPose = const {};
  Map<String, dynamic> capabilities = const {};

  Future<void> connect() async {
    _channel.setMethodCallHandler(_handleNativeCall);
    try {
      final info = await _channel.invokeMapMethod<String, dynamic>('attach');
      if (_disposed) return;
      final value = info ?? const <String, dynamic>{};
      gpuAvailable = value['isAvailable'] as bool? ?? false;
      gpuDescription = value['gpuDescription'] as String? ?? '';
      motionEnabled = value['motionEnabled'] as bool? ?? false;
      cameraPose = Map<String, dynamic>.from(
        value['cameraPose'] as Map? ?? const {},
      );
      capabilities = Map<String, dynamic>.from(
        value['capabilities'] as Map? ?? const {},
      );
      _connected = true;
      status = gpuAvailable
          ? 'تم الاتصال بعارض SplatKit؛ ننتظر أول إطار GPU.'
          : 'تم إنشاء العارض؛ يجري تهيئة Vulkan والتحقق من الجهاز.';
      notifyListeners();
      await refreshStats();
      _statsTimer?.cancel();
      _statsTimer = Timer.periodic(
        const Duration(milliseconds: 600),
        (_) => unawaited(refreshStats()),
      );
    } on PlatformException catch (exception) {
      _setError(exception.message ?? exception.code);
    } catch (exception) {
      _setError(exception.toString());
    }
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (_disposed || call.method != 'event') return;
    final event = Map<String, dynamic>.from(call.arguments as Map);
    final type = event['type'] as String? ?? '';
    switch (type) {
      case 'worldReady':
        worldReady = true;
        status = 'تم رفع العالم إلى GPU (' +
            (event['splatCount'] ?? 0).toString() +
            ' نقطة). ننتظر اكتمال أول إطار.';
        error = null;
        break;
      case 'worldFrameReady':
        worldReady = true;
        firstFrameReady = true;
        gpuAvailable = true;
        status = 'تم رسم أول إطار Gaussian Splat بنجاح على GPU.';
        error = null;
        break;
      case 'gpuFailed':
      case 'gpuUnavailable':
        gpuAvailable = false;
        status = 'تعذّر تشغيل مسار Vulkan.';
        error = event['message'] as String? ?? 'GPU initialization failed';
        break;
      case 'worldFailed':
        status = 'تعذّر تحميل مشهد Gaussian Splat.';
        error = event['message'] as String? ?? 'World load failed';
        break;
      case 'colliderReady':
        status = 'تم تحميل Collider؛ أصبح وضع الحركة متاحاً.';
        error = null;
        break;
      case 'colliderFailed':
        status = 'تعذّر تحميل Collider.';
        error = event['message'] as String? ?? 'Collider load failed';
        break;
      case 'cameraPose':
        cameraPose = event;
        break;
      default:
        return;
    }
    notifyListeners();
  }

  Future<void> refreshStats() async {
    if (_disposed || !_connected) return;
    try {
      final value = await _channel.invokeMapMethod<String, dynamic>('readStats');
      if (_disposed || value == null) return;
      stats = value;
      notifyListeners();
    } on PlatformException catch (exception) {
      if (!_disposed) {
        error = exception.message ?? exception.code;
        notifyListeners();
      }
    }
  }

  Future<void> applyQuality(String preset) async {
    final accepted = await _invoke('applyQuality', {'preset': preset});
    if (accepted == true) {
      quality = preset;
      notifyListeners();
    }
  }

  Future<bool> setMotionEnabled(bool enabled) async {
    final value = await _invoke('setMotionEnabled', {'enabled': enabled});
    motionEnabled = value is bool ? value : false;
    notifyListeners();
    return motionEnabled;
  }

  Future<bool> orbit(double azimuth, double elevation) async {
    final value = await _invoke('orbit', {
      'azimuth': azimuth,
      'elevation': elevation,
    });
    return value is bool ? value : false;
  }

  Future<bool> dolly(double delta) async {
    final value = await _invoke('dolly', {'delta': delta});
    return value is bool ? value : false;
  }

  Future<bool> focus(double x, double y) async {
    final value = await _invoke('focus', {'x': x, 'y': y});
    return value is bool ? value : false;
  }

  Future<void> look(double yaw, double pitch) async {
    await _invoke('look', {'yaw': yaw, 'pitch': pitch});
  }

  Future<void> setAnchor({
    required double x,
    required double y,
    required double z,
  }) async {
    await _invoke('setAnchor', {'x': x, 'y': y, 'z': z});
  }

  Future<void> setWalkVelocity(double forward, double right) async {
    await _invoke('setWalkVelocity', {
      'forward': forward,
      'right': right,
    });
  }

  Future<void> setCameraPose({
    required double x,
    required double y,
    required double z,
    double yaw = 0,
    double pitch = 0,
  }) async {
    await _invoke('setCameraPose', {
      'x': x,
      'y': y,
      'z': z,
      'yaw': yaw,
      'pitch': pitch,
    });
  }

  Future<void> setRenderScale(double value) async {
    await _invoke('setRenderScale', {'value': value});
  }

  Future<void> setShDegree(int value) async {
    await _invoke('setShDegree', {'value': value});
  }

  Future<void> setMaxFramesPerSecond(double? value) async {
    await _invoke('setMaxFramesPerSecond', {'value': value});
  }

  Future<void> loadCollider(String path) async {
    await _invoke('loadCollider', {'path': path});
  }

  Future<void> loadTiledWorld(String path) async {
    await _invoke('loadTiledWorld', {'path': path});
  }

  Future<Map<String, dynamic>?> applyRenderPolicy(
    Map<String, Object?> policy,
  ) async {
    final value = await _invoke('applyRenderPolicy', {'policy': policy});
    if (value == null) return null;
    final result = Map<String, dynamic>.from(value as Map);
    renderPolicyAccepted = result['accepted'] as bool? ?? false;
    renderPolicyWarnings = List<String>.from(
      result['warnings'] as List? ?? const [],
    );
    final policyError = result['error'] as String?;
    if (policyError != null) error = policyError;
    notifyListeners();
    return result;
  }

  Future<void> setHiZOcclusion(bool enabled) async {
    if (enabled && capabilities['supportsHiZOcclusion'] != true) {
      renderPolicyAccepted = false;
      renderPolicyWarnings = const [
        'Hi-Z occlusion is not supported by this Vulkan device.',
      ];
      notifyListeners();
      return;
    }
    final result = await applyRenderPolicy({
      'lodErrorPixels': 1.0,
      'lodSplatLimit': 0,
      'alphaThreshold': 1 / 255,
      'subpixelThreshold': 1.0,
      'enableFrustumCulling': true,
      'enableHiZOcclusion': enabled,
      'enableEarlyTermination': true,
      'sortDepth': 16,
    });
    if (result?['accepted'] == true) {
      hiZOcclusionEnabled = enabled;
      error = null;
    } else if (result?['error'] != null) {
      error = result!['error'] as String;
    }
    notifyListeners();
  }

  Future<void> startBenchmark({double seconds = 10}) async {
    await _invoke('startBenchmark', {'seconds': seconds});
  }

  Future<Object?> _invoke(
    String method, [
    Map<String, Object?> arguments = const {},
  ]) async {
    if (_disposed || !_connected) return null;
    try {
      return await _channel.invokeMethod<Object?>(method, arguments);
    } on PlatformException catch (exception) {
      _setError(exception.message ?? exception.code);
      return null;
    } catch (exception) {
      _setError(exception.toString());
      return null;
    }
  }

  void _setError(String message) {
    error = message;
    status = 'حدث خطأ في عارض Gaussian Splat.';
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _statsTimer?.cancel();
    _statsTimer = null;
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
