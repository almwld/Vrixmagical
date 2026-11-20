import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:virxmagical/domain/captured_frame.dart';
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

    test('persists source images and marks legacy camera pose as untrusted', () async {
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
      expect(text, contains('unverified-unsynchronized'));
      expect(text, contains('"cameraPose":null'));
      expect(text, contains('"schemaVersion":3'));
      expect(await File('${store.directory.path}/view_001.jpg').exists(), isTrue);
      expect(await File('${store.directory.path}/mask_001.png').exists(), isTrue);
    });


    test('persists synchronized depth and confidence buffers with frame provenance', () async {
      final frame = CapturedFrame(
        rgbBytes: Uint8List.fromList([1, 2, 3]),
        frameTimestampNs: 100,
        rgbTimestampNs: 99,
        rgbIntrinsics: const CameraIntrinsics(
          fx: 500, fy: 500, cx: 320, cy: 240, width: 640, height: 480,
        ),
        cameraPose: Float64List.fromList([
          1, 0, 0, 0,
          0, 1, 0, 0,
          0, 0, 1, 0,
          0, 0, 0, 1,
        ]),
        trackingState: VrixTrackingState.tracking,
        depthSupport: VrixDepthSupport.rawOnly,
        depth: DepthFrame(
          valuesMeters: Float32List.fromList([1, 0, 2, 3]),
          confidence: Uint8List.fromList([255, 0, 200, 220]),
          width: 2,
          height: 2,
          frameTimestampNs: 100,
          imageTimestampNs: 90,
          isRaw: true,
          isReprojected: true,
          confidenceAvailable: true,
          intrinsics: const CameraIntrinsics(
            fx: 1, fy: 1, cx: .5, cy: .5, width: 2, height: 2,
          ),
        ),
      );
      final store = await ObjectScanStore.create(
        displayName: 'RGB-D sample',
        rootDirectory: root,
      );
      await store.addView(ObjectScanView(
        imageFile: source,
        maskPng: const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
        width: 640,
        height: 480,
        maskWidth: 2,
        maskHeight: 2,
        cameraPose: frame.cameraPose.toList(),
        cameraPoseSynchronized: true,
        capturedFrame: frame,
        promptX: .5,
        promptY: .5,
      ));
      final directory = store.directory;
      final manifest = await File('${directory.path}/scan_manifest.json').readAsString();
      expect(manifest, contains('"captureKind":"masked-multiview-rgbd"'));
      expect(manifest, contains('"isRaw":true'));
      expect(manifest, contains('"isReprojected":true'));
      expect(manifest, contains('"confidenceAvailable":true'));
      expect(await File('${directory.path}/depth_001.f32le').length(), 16);
      expect(await File('${directory.path}/confidence_001.u8').readAsBytes(),
          [255, 0, 200, 220]);
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

    test('rolls back in-memory completion when manifest commit fails', () async {
      final store = await ObjectScanStore.create(
        displayName: 'Desk scan',
        rootDirectory: root,
      );
      await store.addView(view(.2));
      await store.addView(view(.5));
      await store.addView(view(.7));

      // Force the temporary manifest write to fail without damaging the
      // previously committed collecting manifest.
      await Directory(
        '${store.directory.path}/scan_manifest.json.tmp',
      ).create();

      await expectLater(store.complete(), throwsA(isA<FileSystemException>()));
      expect(store.snapshot.isComplete, isFalse);

      // Remove the injected filesystem fault before verifying that the
      // rolled-back session can accept another view and commit its manifest.
      await Directory(
        '${store.directory.path}/scan_manifest.json.tmp',
      ).delete();

      await expectLater(store.addView(view(.8)), completes);
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
