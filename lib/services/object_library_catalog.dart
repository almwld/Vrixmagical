import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/vrix_object.dart';

class CatalogAsset {
  const CatalogAsset({
    required this.object,
    required this.category,
    required this.license,
    required this.sourceName,
    this.attribution,
  });

  final VrixObject object;
  final String category;
  final String license;
  final String sourceName;
  final String? attribution;

  factory CatalogAsset.fromJson(Map<String, dynamic> json) {
    final asset = CatalogAsset(
      object: VrixObject.fromJson(
        Map<String, dynamic>.from(json['object'] as Map),
      ),
      category: json['category'] as String,
      license: json['license'] as String,
      sourceName: json['sourceName'] as String,
      attribution: json['attribution'] as String?,
    );
    asset.validate();
    return asset;
  }

  Map<String, dynamic> toJson() => {
        'category': category,
        'license': license,
        'sourceName': sourceName,
        if (attribution != null) 'attribution': attribution,
        'object': object.toJson(),
      };

  void validate() {
    if (category.trim().isEmpty || sourceName.trim().isEmpty ||
        license.trim().isEmpty) {
      throw const FormatException(
        'Catalog entries require category, source and license metadata.',
      );
    }
    final path = object.meshPath.replaceAll('\\', '/');
    if (path.startsWith('/') ||
        path.split('/').any((segment) => segment == '..') ||
        !RegExp(r'\.(glb|gltf)$', caseSensitive: false).hasMatch(path)) {
      throw const FormatException(
        'Catalog meshPath must be a safe relative GLB/GLTF path.',
      );
    }
  }
}

/// Loads a versioned, license-aware catalog. It intentionally does not invent
/// or bundle third-party model files: each entry is accepted only when its
/// referenced asset is actually present in the packaged application.
class ObjectLibraryCatalog {
  ObjectLibraryCatalog._(this.assets);

  final List<CatalogAsset> assets;

  static Future<ObjectLibraryCatalog> load({
    AssetBundle bundle = rootBundle,
    String manifestPath = 'assets/models/manifest.json',
  }) async {
    final raw = await bundle.loadString(manifestPath);
    return decode(raw);
  }

  factory ObjectLibraryCatalog.decode(String raw) {
    final root = jsonDecode(raw) as Map<String, dynamic>;
    if (root['schemaVersion'] != 1) {
      throw const FormatException('Unsupported object catalog schema version.');
    }
    final entries = (root['assets'] as List? ?? const [])
        .map((entry) => CatalogAsset.fromJson(
              Map<String, dynamic>.from(entry as Map),
            ))
        .toList(growable: false);
    final ids = <String>{};
    for (final entry in entries) {
      if (!ids.add(entry.object.id)) {
        throw FormatException('Duplicate catalog object id: ${entry.object.id}');
      }
    }
    return ObjectLibraryCatalog._(List.unmodifiable(entries));
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': 1,
        'assets': assets.map((asset) => asset.toJson()).toList(),
      };

  List<CatalogAsset> search({
    String? query,
    String? category,
  }) {
    final needle = query?.trim().toLowerCase() ?? '';
    final selectedCategory = category?.trim().toLowerCase();
    return assets.where((asset) {
      if (selectedCategory != null && selectedCategory.isNotEmpty &&
          asset.category.toLowerCase() != selectedCategory) {
        return false;
      }
      if (needle.isEmpty) return true;
      return asset.object.displayName.toLowerCase().contains(needle) ||
          asset.object.tags.any((tag) => tag.toLowerCase().contains(needle));
    }).toList(growable: false);
  }
}


/// Persistent local catalog for user-imported GLB/GLTF files.
class ObjectLibraryStore {
  ObjectLibraryStore._(this.rootDirectory, this._catalog, this._manifestFile);

  final Directory rootDirectory;
  ObjectLibraryCatalog _catalog;
  final File _manifestFile;

  ObjectLibraryCatalog get catalog => _catalog;

  static Future<ObjectLibraryStore> open({
    Directory? supportDirectory,
    AssetBundle bundle = rootBundle,
    String manifestPath = 'assets/models/manifest.json',
  }) async {
    final root = supportDirectory ?? await getApplicationSupportDirectory();
    await root.create(recursive: true);
    final file = File('${root.path}/object_library.json');
    final raw = await file.exists()
        ? await file.readAsString()
        : await bundle.loadString(manifestPath);
    return ObjectLibraryStore._(root, ObjectLibraryCatalog.decode(raw), file);
  }

  Future<CatalogAsset> importModel(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const FileSystemException('Selected 3D model does not exist.');
    }
    final extension = source.path.split('.').last.toLowerCase();
    if (extension != 'glb' && extension != 'gltf') {
      throw const FormatException('Only GLB and GLTF models can be imported.');
    }

    final originalName = source.uri.pathSegments.isEmpty
        ? 'model'
        : source.uri.pathSegments.last;
    final stem = originalName.replaceFirst(RegExp(r'\\.(glb|gltf)$', caseSensitive: false), '');
    final safeStem = stem.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]+'), '-');
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final fileName = '${timestamp}_${safeStem.isEmpty ? 'model' : safeStem}.$extension';
    final relativePath = 'models/imported/$fileName';
    final destination = File('${rootDirectory.path}/$relativePath');
    await destination.parent.create(recursive: true);
    await source.copy(destination.path);

    final tags = safeStem.split(RegExp(r'[-_]+')).where((tag) => tag.isNotEmpty).toSet().toList();
    final object = VrixObject(
      id: 'import-$timestamp',
      source: ObjectSource.imported,
      displayName: stem.isEmpty ? 'Imported model' : stem,
      meshPath: relativePath,
      physics: const PhysicsProfile(),
      tags: tags.isEmpty ? const ['imported', '3d-model'] : tags,
      metadata: const {'userProvided': true, 'format': 'glb-or-gltf'},
    );
    final asset = CatalogAsset(
      object: object,
      category: 'imported',
      license: 'User-provided',
      sourceName: 'Local import',
    );
    asset.validate();
    _catalog = ObjectLibraryCatalog._(
      List.unmodifiable([..._catalog.assets, asset]),
    );
    await _save();
    return asset;
  }

  Future<void> _save() async {
    await _manifestFile.parent.create(recursive: true);
    final temporary = File('${_manifestFile.path}.tmp');
    await temporary.writeAsString(jsonEncode(_catalog.toJson()), flush: true);
    if (await _manifestFile.exists()) await _manifestFile.delete();
    await temporary.rename(_manifestFile.path);
  }
}
