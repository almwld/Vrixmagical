import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:virxmagical/services/object_scan_store.dart';

void main() {
  group('ObjectScanStore', () {
    late Directory root;
    late File source;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('vrix-scan-test-');
      source = File('${root.path}/capture.jpg');
      await source.writeAsBytes([0xff, 0xd8, 0xff, 0xd9]);
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    ObjectScanView view(double x) => ObjectScanView(
          imageFile: source,
          maskPng: const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
          width: 640,
          height: 480,
          maskWidth: 256,
          maskHeight: 256,
          cameraPose: List<double>.filled(16, 0)..[0] = 1,
          promptX: x,
          promptY: .5,
        );

    test('persists source images, masks and a versioned manifest', () async {
      final store = await ObjectScanStore.create(
        displayName: 'Desk object',
        rootDirectory: root,
      );
      await store.addView(view(.2));
      await store.addView(view(.5));
      final manifest = File('${store.directory.path}/scan_manifest.json');
      expect(await manifest.exists(), isTrue);
      final text = await manifest.readAsString();
      expect(text, contains('"captureKind":"masked-multiview-rgb"'));
      expect(text, contains('"viewCount":2'));
      expect(text, contains('"maskWidth":256'));
      expect(text, contains('column-major-world-from-camera-meters'));
      expect(await File('${store.directory.path}/view_001.jpg').exists(), isTrue);
      expect(await File('${store.directory.path}/mask_001.png').exists(), isTrue);
    });

    test('requires at least three views before completing', () async {
      final store = await ObjectScanStore.create(
        displayName: 'Chair',
        rootDirectory: root,
      );
      await store.addView(view(.2));
      await expectLater(store.complete(), throwsStateError);
      await store.addView(view(.5));
      await store.addView(view(.7));
      final completed = await store.complete();
      expect(completed.isComplete, isTrue);
      expect(completed.viewCount, 3);
      await expectLater(store.addView(view(.8)), throwsStateError);
    });

    test('rejects invalid camera poses and prompt coordinates', () async {
      final store = await ObjectScanStore.create(
        displayName: 'Lamp',
        rootDirectory: root,
      );
      await expectLater(store.addView(view(1.2)), throwsFormatException);
      await expectLater(
        store.addView(ObjectScanView(
          imageFile: source,
          maskPng: const [1, 2, 3, 4, 5, 6, 7, 8],
          width: 10,
          height: 10,
          promptX: .5,
          promptY: .5,
          cameraPose: const [1, 2, 3],
        )),
        throwsFormatException,
      );
      final missing = File('${root.path}/missing.jpg');
      await expectLater(
        store.addView(ObjectScanView(
          imageFile: missing,
          maskPng: const [1, 2, 3, 4, 5, 6, 7, 8],
          width: 10,
          height: 10,
          promptX: .5,
          promptY: .5,
        )),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}
