import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:virxmagical/services/splat_tiled_world_importer.dart';

void main() {
  group('SplatTiledWorldImporter', () {
    late Directory temporaryRoot;
    late Directory source;
    late Directory documents;

    setUp(() async {
      temporaryRoot = await Directory.systemTemp.createTemp('splat_tiles_test_');
      source = Directory(temporaryRoot.path + '/source');
      documents = Directory(temporaryRoot.path + '/documents');
      await source.create(recursive: true);
      await documents.create(recursive: true);
    });

    tearDown(() async {
      if (await temporaryRoot.exists()) {
        await temporaryRoot.delete(recursive: true);
      }
    });

    test('copies tileset and nested assets preserving relative paths', () async {
      final tileDirectory = Directory(source.path + '/tiles/0');
      await tileDirectory.create(recursive: true);
      await File(source.path + '/tileset.json').writeAsString(
        '{"root":"tiles/0/tile.spz"}',
      );
      await File(tileDirectory.path + '/tile.spz').writeAsBytes([1, 2, 3, 4]);

      final result = await const SplatTiledWorldImporter().copyDirectory(
        source: source,
        destinationRoot: documents,
      );

      expect(result.fileCount, 2);
      expect(await result.tilesetFile.exists(), isTrue);
      expect(
        await File(
          result.tilesetFile.parent.path + '/tiles/0/tile.spz',
        ).exists(),
        isTrue,
      );
      expect(result.totalBytes, greaterThan(0));
    });

    test('finds a nested tileset when no root tileset exists', () async {
      final nested = Directory(source.path + '/scene-a');
      await nested.create(recursive: true);
      await File(nested.path + '/tileset.json').writeAsString('{}');

      final result = await const SplatTiledWorldImporter().copyDirectory(
        source: source,
        destinationRoot: documents,
      );

      expect(result.tilesetFile.path, endsWith('/scene-a/tileset.json'));
    });

    test('rejects missing tileset and configured resource limits', () async {
      await File(source.path + '/not-a-tileset.txt').writeAsString('x');
      await expectLater(
        const SplatTiledWorldImporter().copyDirectory(
          source: source,
          destinationRoot: documents,
        ),
        throwsStateError,
      );

      await File(source.path + '/tileset.json').writeAsString('{}');
      await expectLater(
        const SplatTiledWorldImporter(maxFiles: 1).copyDirectory(
          source: source,
          destinationRoot: documents,
        ),
        throwsStateError,
      );
    });
  });
}
