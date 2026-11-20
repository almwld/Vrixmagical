import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reality/managers/ar_object_manager.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ARObjectManager deformable mesh bridge', () {
    const viewId = 41;
    const channelName = 'flutter_reality/mesh_41';
    final channel = const MethodChannel(channelName);

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('adds, updates and removes one renderer-owned mesh', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'add' ? true : null;
      });
      final manager = ARObjectManager(viewId);
      const positions = <double>[
        0, 0, 0,
        1, 0, 0,
        0, 1, 0,
        0, 0, 1,
      ];
      const indices = <int>[
        0, 2, 1,
        0, 1, 3,
        1, 2, 3,
        2, 0, 3,
      ];

      expect(
        await manager.addDeformableMesh(
          id: 'soft-body-test',
          positions: positions,
          triangleIndices: indices,
          worldTransform: Matrix4.identity(),
        ),
        isTrue,
      );
      await manager.updateDeformableMesh(
        id: 'soft-body-test',
        positions: positions.map((value) => value + 0.01).toList(),
        worldTransform: Matrix4.identity(),
      );
      await manager.removeDeformableMesh('soft-body-test');

      expect(calls.map((call) => call.method), ['add', 'update', 'remove']);
      final addArguments = Map<String, Object?>.from(calls.first.arguments as Map);
      expect(addArguments['id'], 'soft-body-test');
      expect(addArguments['indices'], indices);
      expect((addArguments['positions'] as List).length, positions.length);
    });

    test('rejects invalid topology and non-invertible transforms before channel calls', () async {
      var invoked = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        invoked = true;
        return true;
      });
      final manager = ARObjectManager(viewId);

      await expectLater(
        manager.addDeformableMesh(
          id: 'invalid',
          positions: const [0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1],
          triangleIndices: const [0, 1, 99],
          worldTransform: Matrix4.identity(),
        ),
        throwsArgumentError,
      );
      await expectLater(
        manager.updateDeformableMesh(
          id: 'invalid',
          positions: const [0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1],
          worldTransform: Matrix4.zero(),
        ),
        throwsArgumentError,
      );
      expect(invoked, isFalse);
    });
  });
}
