import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A single RGB view and its foreground mask from one object-scan session.
/// Camera pose/depth are deliberately nullable until the ARCore bridge supplies
/// calibrated measurements; a photo-only bundle must never masquerade as a mesh.
class ObjectScanView {
  const ObjectScanView({
    required this.imageFile,
    required this.maskPng,
    required this.width,
    required this.height,
    required this.promptX,
    required this.promptY,
    DateTime? capturedAt,
  }) : capturedAt = capturedAt ?? DateTime.now();

  final File imageFile;
  final List<int> maskPng;
  final int width;
  final int height;
  final double promptX;
  final double promptY;
  final DateTime capturedAt;

  void validate() {
    if (width < 1 || height < 1 || width > 12000 || height > 12000) {
      throw const FormatException('Scan image dimensions are invalid.');
    }
    if (maskPng.length < 8) {
      throw const FormatException('A non-empty PNG foreground mask is required.');
    }
    if (!promptX.isFinite || !promptY.isFinite ||
        promptX < 0 || promptX > 1 || promptY < 0 || promptY > 1) {
      throw const FormatException('The segmentation prompt must be normalized.');
    }
  }
}

class ObjectScanSession {
  const ObjectScanSession({
    required this.id,
    required this.displayName,
    required this.directory,
    required this.viewCount,
    required this.isComplete,
  });

  final String id;
  final String displayName;
  final Directory directory;
  final int viewCount;
  final bool isComplete;

  String get manifestPath => '${directory.path}/scan_manifest.json';
}

/// Durable multi-view capture store. It saves source photos and transparent
/// masks separately, then atomically updates a versioned manifest.
class ObjectScanStore {
  ObjectScanStore._(this._directory, this._manifest, this.id, this.displayName);

  final Directory _directory;
  final File _manifest;
  final String id;
  final String displayName;
  final List<Map<String, Object?>> _views = [];
  final DateTime _createdAt = DateTime.now().toUtc();
  bool _complete = false;

  int get viewCount => _views.length;
  Directory get directory => _directory;

  static Future<ObjectScanStore> create({
    required String displayName,
    Directory? rootDirectory,
  }) async {
    final name = displayName.trim();
    if (name.isEmpty || name.length > 80) {
      throw const FormatException('Scan name must contain 1–80 characters.');
    }
    final root = rootDirectory ?? await getApplicationSupportDirectory();
    final id = 'scan-${DateTime.now().toUtc().microsecondsSinceEpoch}';
    final directory = Directory('${root.path}/vrix_scans/$id');
    await directory.create(recursive: true);
    final store = ObjectScanStore._(
      directory,
      File('${directory.path}/scan_manifest.json'),
      id,
      name,
    );
    await store._writeManifest();
    return store;
  }

  Future<void> addView(ObjectScanView view) async {
    if (_complete) throw StateError('This scan session is already complete.');
    view.validate();
    if (!await view.imageFile.exists()) {
      throw const FileSystemException('Captured source image does not exist.');
    }
    if (_views.length >= 80) {
      throw StateError('A scan session is limited to 80 views.');
    }

    final index = _views.length + 1;
    final extension = view.imageFile.path.toLowerCase().endsWith('.png')
        ? 'png'
        : 'jpg';
    final imageName = 'view_${index.toString().padLeft(3, '0')}.$extension';
    final maskName = 'mask_${index.toString().padLeft(3, '0')}.png';
    final imageTarget = File('${_directory.path}/$imageName');
    final maskTarget = File('${_directory.path}/$maskName');
    await view.imageFile.copy(imageTarget.path);
    try {
      await maskTarget.writeAsBytes(view.maskPng, flush: true);
      _views.add({
        'index': index,
        'image': imageName,
        'mask': maskName,
        'width': view.width,
        'height': view.height,
        'capturedAt': view.capturedAt.toUtc().toIso8601String(),
        'prompt': {'x': view.promptX, 'y': view.promptY},
        'cameraPose': null,
        'depthMap': null,
      });
      await _writeManifest();
    } catch (_) {
      if (_views.isNotEmpty && _views.last['index'] == index) _views.removeLast();
      if (await imageTarget.exists()) await imageTarget.delete();
      if (await maskTarget.exists()) await maskTarget.delete();
      rethrow;
    }
  }

  Future<ObjectScanSession> complete() async {
    if (_views.length < 3) {
      throw StateError('Capture at least three distinct views before completing a scan.');
    }
    _complete = true;
    await _writeManifest();
    return snapshot;
  }

  ObjectScanSession get snapshot => ObjectScanSession(
        id: id,
        displayName: displayName,
        directory: _directory,
        viewCount: viewCount,
        isComplete: _complete,
      );

  Future<void> _writeManifest() async {
    final payload = <String, Object?>{
      'schemaVersion': 1,
      'id': id,
      'displayName': displayName,
      'source': 'captured',
      'captureKind': 'masked-multiview-rgb',
      'createdAt': _createdAt.toIso8601String(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'status': _complete ? 'captured' : 'collecting',
      'viewCount': _views.length,
      'reconstruction': {
        'status': 'not_started',
        'output': null,
        'note': 'RGB views and masks only; calibrated camera poses and depth are not yet available.',
      },
      'views': _views,
    };
    final temporary = File('${_manifest.path}.tmp');
    await temporary.writeAsString(jsonEncode(payload), flush: true);
    await temporary.rename(_manifest.path);
  }
}
