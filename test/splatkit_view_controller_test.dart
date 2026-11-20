import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virxmagical/services/splatkit_view_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('connects, polls renderer stats and forwards typed controls', () async {
    const channel = MethodChannel('virxmagical/splat_view/42');
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'attach':
          return {
            'isAvailable': true,
            'gpuDescription': 'Test Vulkan GPU',
            'motionEnabled': false,
            'cameraPose': {'x': 1.0, 'y': 2.0, 'z': 3.0},
            'capabilities': {'supportsSubgroups': true, 'supportsHiZOcclusion': true},
          };
        case 'readStats':
          return {
            'fps': 60.0,
            'gpuMillis': 4.5,
            'loadedSplats': 1200,
            'drawnSplats': 1100,
          };
        case 'applyQuality':
        case 'setMotionEnabled':
          return true;
        case 'applyRenderPolicy':
          return {'accepted': true, 'warnings': <String>[]};
        case 'orbit':
        case 'dolly':
        case 'focus':
          return true;
        default:
          return null;
      }
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final controller = SplatKitViewController(42);
    await controller.connect();

    expect(controller.isConnected, isTrue);
    expect(controller.gpuAvailable, isTrue);
    expect(controller.gpuDescription, 'Test Vulkan GPU');
    expect(controller.stats['fps'], 60.0);
    expect(controller.stats['drawnSplats'], 1100);

    await controller.applyQuality('high');
    expect(controller.quality, 'high');
    await controller.setHiZOcclusion(true);
    expect(controller.hiZOcclusionEnabled, isTrue);
    expect(controller.renderPolicyAccepted, isTrue);
    expect(await controller.setMotionEnabled(true), isTrue);
    expect(await controller.orbit(0.2, 0.1), isTrue);
    expect(await controller.dolly(-0.1), isTrue);
    expect(await controller.focus(0.5, 0.5), isTrue);

    expect(calls, containsAll([
      'attach',
      'readStats',
      'applyQuality',
      'setMotionEnabled',
      'applyRenderPolicy',
      'orbit',
      'dolly',
      'focus',
    ]));
    controller.dispose();
  });
}
