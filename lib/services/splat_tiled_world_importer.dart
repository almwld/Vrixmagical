import 'dart:io';

class SplatTiledWorldImportResult {
  const SplatTiledWorldImportResult({
    required this.tilesetFile,
    required this.fileCount,
    required this.totalBytes,
  });

  final File tilesetFile;
  final int fileCount;
  final int totalBytes;
}

/// Copies a selected tileset directory into app-private storage while
/// preserving relative tile paths required by SplatKit's streaming loader.
class SplatTiledWorldImporter {
  const SplatTiledWorldImporter({
    this.maxFiles = 20000,
    this.maxTotalBytes = 4 * 1024 * 1024 * 1024,
  });

  final int maxFiles;
  final int maxTotalBytes;

  Future<SplatTiledWorldImportResult> copyDirectory({
    required Directory source,
    required Directory destinationRoot,
    void Function(int copiedFiles, int totalFiles)? onProgress,
  }) async {
    final sourceDirectory = source.absolute;
    if (!await sourceDirectory.exists()) {
      throw StateError('The selected tiled-world directory does not exist.');
    }
    final separator = Platform.pathSeparator;
    final sourcePrefix = sourceDirectory.path.endsWith(separator)
        ? sourceDirectory.path
        : sourceDirectory.path + separator;

    String relativePath(File file) {
      final absolutePath = file.absolute.path;
      if (!absolutePath.startsWith(sourcePrefix)) {
        throw StateError('A selected tile escaped the source directory.');
      }
      final relative = absolutePath.substring(sourcePrefix.length);
      if (relative.isEmpty ||
          relative.split(separator).any((segment) => segment == '..')) {
        throw StateError('The tiled-world directory contains an invalid path.');
      }
      return relative;
    }

    final files = <File>[];
    File? rootTileset;
    File? nestedTileset;
    var totalBytes = 0;

    await for (final entity in sourceDirectory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final file = entity;
      final relative = relativePath(file);
      totalBytes += await file.length();
      if (totalBytes > maxTotalBytes) {
        throw StateError('The selected tiled world exceeds the import size limit.');
      }
      files.add(file);
      if (files.length > maxFiles) {
        throw StateError('The selected tiled world contains too many files.');
      }
      if (relative == 'tileset.json') {
        rootTileset = file;
      } else if (relative.split(separator).last == 'tileset.json') {
        nestedTileset ??= file;
      }
    }

    final sourceTileset = rootTileset ?? nestedTileset;
    if (sourceTileset == null) {
      throw StateError('No tileset.json was found in the selected directory.');
    }

    final relativeTileset = relativePath(sourceTileset);
    final targetRoot = Directory(
      destinationRoot.absolute.path +
          separator +
          'splat_tiled_worlds' +
          separator +
          DateTime.now().microsecondsSinceEpoch.toString(),
    );

    try {
      await targetRoot.create(recursive: true);
      for (var index = 0; index < files.length; index++) {
        final sourceFile = files[index];
        final relative = relativePath(sourceFile);
        final destination = File(
          targetRoot.path + separator + relative,
        );
        await destination.parent.create(recursive: true);
        await sourceFile.copy(destination.path);
        onProgress?.call(index + 1, files.length);
      }

      final copiedTileset = File(
        targetRoot.path + separator + relativeTileset,
      );
      if (!await copiedTileset.exists()) {
        throw StateError('The copied tileset.json could not be verified.');
      }
      return SplatTiledWorldImportResult(
        tilesetFile: copiedTileset,
        fileCount: files.length,
        totalBytes: totalBytes,
      );
    } catch (_) {
      if (await targetRoot.exists()) {
        await targetRoot.delete(recursive: true);
      }
      rethrow;
    }
  }
}
