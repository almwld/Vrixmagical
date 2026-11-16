import 'dart:convert';

import 'package:flutter/services.dart';

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
