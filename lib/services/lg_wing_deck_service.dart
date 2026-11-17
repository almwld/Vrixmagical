import 'package:flutter/services.dart';

typedef WingDeckAction = void Function(String action, Map<String, Object?> data);

/// Bridges the Flutter AR scene to the LG Wing's secondary presentation display.
class LgWingDeckService {
  LgWingDeckService._();

  static final LgWingDeckService instance = LgWingDeckService._();
  static const MethodChannel _channel = MethodChannel('vrix/wing_deck');

  WingDeckAction? _onAction;
  bool _initialized = false;

  Future<bool> show({required WingDeckAction onAction}) async {
    _onAction = onAction;
    if (!_initialized) {
      _channel.setMethodCallHandler(_handleNativeCall);
      _initialized = true;
    }
    try {
      return await _channel.invokeMethod<bool>('show') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> updateTelemetry({
    required double fps,
    required int placedObjects,
    required bool physicsEnabled,
    required String physicsLabel,
    required double touchThreshold,
  }) async {
    try {
      await _channel.invokeMethod<void>('updateTelemetry', <String, Object>{
        'fps': fps,
        'placedObjects': placedObjects,
        'physicsEnabled': physicsEnabled,
        'physicsLabel': physicsLabel,
        'touchThreshold': touchThreshold,
      });
    } on PlatformException {
      // The main AR session remains usable if the secondary display disappears.
    } on MissingPluginException {
      // Non-Android/test environments do not provide the native bridge.
    }
  }

  Future<void> hide() async {
    try {
      await _channel.invokeMethod<void>('hide');
    } on PlatformException {
      // Best-effort cleanup.
    } on MissingPluginException {
      // Best-effort cleanup.
    }
    _onAction = null;
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != 'deckAction') return;
    final arguments = call.arguments;
    if (arguments is! Map) return;
    final action = arguments['action'];
    if (action is! String) return;
    final data = <String, Object?>{};
    arguments.forEach((key, value) {
      if (key is String && key != 'action') data[key] = value;
    });
    _onAction?.call(action, data);
  }
}
