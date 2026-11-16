import 'dart:convert';

enum ObjectSource { captured, library, generated, imported }

enum ColliderShape { box, sphere, capsule, convexHull, triangleMesh, none }

/// A world-space transform. Positions are metres; rotation is an XYZW unit
/// quaternion. Keeping this renderer-independent lets AR, physics and storage
/// share the same object identity without depending on ARNode or Jolt types.
class VrixTransform {
  const VrixTransform({
    this.position = const [0, 0, 0],
    this.rotation = const [0, 0, 0, 1],
    this.scale = const [1, 1, 1],
  });

  final List<double> position;
  final List<double> rotation;
  final List<double> scale;

  factory VrixTransform.fromJson(Map<String, dynamic> json) => VrixTransform(
        position: _readVector(json['position'], 3, 'position', fallback: const [0, 0, 0]),
        rotation: _readVector(json['rotation'], 4, 'rotation', fallback: const [0, 0, 0, 1]),
        scale: _readVector(json['scale'], 3, 'scale', fallback: const [1, 1, 1]),
      );

  Map<String, dynamic> toJson() => {
        'position': position,
        'rotation': rotation,
        'scale': scale,
      };

  void validate() {
    _validateVector(position, 3, 'position');
    _validateVector(rotation, 4, 'rotation');
    _validateVector(scale, 3, 'scale');
    if (scale.any((value) => value <= 0)) {
      throw const FormatException('Transform scale values must be positive.');
    }
    final norm = rotation.fold<double>(0, (sum, value) => sum + value * value);
    if (norm < 1e-12) {
      throw const FormatException('Rotation quaternion must not be zero.');
    }
  }
}

class PhysicsProfile {
  const PhysicsProfile({
    this.mass = 1,
    this.collider = ColliderShape.box,
    this.halfExtents = const [0.1, 0.1, 0.1],
    this.radius = 0.1,
    this.halfHeight = 0.2,
    this.friction = 0.55,
    this.restitution = 0.05,
    this.isStatic = false,
    this.continuous = true,
  });

  final double mass;
  final ColliderShape collider;
  final List<double> halfExtents;
  final double radius;
  final double halfHeight;
  final double friction;
  final double restitution;
  final bool isStatic;
  final bool continuous;

  factory PhysicsProfile.fromJson(Map<String, dynamic> json) {
    final profile = PhysicsProfile(
      mass: _readNumber(json['mass'], 1),
      collider: ColliderShape.values.firstWhere(
        (value) => value.name == (json['collider'] ?? 'box'),
        orElse: () => throw FormatException('Unknown collider: ${json['collider']}'),
      ),
      halfExtents: _readVector(json['halfExtents'], 3, 'halfExtents',
          fallback: const [0.1, 0.1, 0.1]),
      radius: _readNumber(json['radius'], 0.1),
      halfHeight: _readNumber(json['halfHeight'], 0.2),
      friction: _readNumber(json['friction'], 0.55),
      restitution: _readNumber(json['restitution'], 0.05),
      isStatic: json['isStatic'] == true,
      continuous: json['continuous'] != false,
    );
    profile.validate();
    return profile;
  }

  Map<String, dynamic> toJson() => {
        'mass': mass,
        'collider': collider.name,
        'halfExtents': halfExtents,
        'radius': radius,
        'halfHeight': halfHeight,
        'friction': friction,
        'restitution': restitution,
        'isStatic': isStatic,
        'continuous': continuous,
      };

  void validate() {
    if (!mass.isFinite || mass <= 0) {
      throw const FormatException('Physics mass must be positive and finite.');
    }
    _validateVector(halfExtents, 3, 'halfExtents');
    if (halfExtents.any((value) => value <= 0)) {
      throw const FormatException('Collider half extents must be positive.');
    }
    if (!radius.isFinite || radius <= 0 ||
        !halfHeight.isFinite || halfHeight <= 0) {
      throw const FormatException('Collider dimensions must be positive and finite.');
    }
    if (!friction.isFinite || friction < 0 || friction > 1 ||
        !restitution.isFinite || restitution < 0 || restitution > 1) {
      throw const FormatException('Friction and restitution must be between 0 and 1.');
    }
  }
}

/// Canonical identity shared by scanned, catalog, generated and imported
/// objects. Metadata is JSON-safe and must not contain credentials or secrets.
class VrixObject {
  VrixObject({
    required this.id,
    required this.source,
    required this.displayName,
    required this.meshPath,
    required this.physics,
    required this.tags,
    this.transform = const VrixTransform(),
    Map<String, dynamic> metadata = const {},
  }) : metadata = Map.unmodifiable(metadata) {
    validate();
  }

  final String id;
  final ObjectSource source;
  final String displayName;
  final String meshPath;
  final PhysicsProfile physics;
  final List<String> tags;
  final VrixTransform transform;
  final Map<String, dynamic> metadata;

  factory VrixObject.fromJson(Map<String, dynamic> json) {
    final object = VrixObject(
      id: json['id'] as String,
      source: ObjectSource.values.firstWhere(
        (value) => value.name == json['source'],
        orElse: () => throw FormatException('Unknown object source: ${json['source']}'),
      ),
      displayName: json['displayName'] as String,
      meshPath: json['meshPath'] as String,
      physics: PhysicsProfile.fromJson(
        Map<String, dynamic>.from(json['physics'] as Map? ?? const {}),
      ),
      tags: (json['tags'] as List? ?? const []).cast<String>(),
      transform: VrixTransform.fromJson(
        Map<String, dynamic>.from(json['transform'] as Map? ?? const {}),
      ),
      metadata: Map<String, dynamic>.from(json['metadata'] as Map? ?? const {}),
    );
    return object;
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': 1,
        'id': id,
        'source': source.name,
        'displayName': displayName,
        'meshPath': meshPath,
        'physics': physics.toJson(),
        'tags': tags,
        'transform': transform.toJson(),
        'metadata': metadata,
      };

  String encode() => jsonEncode(toJson());

  factory VrixObject.decode(String value) =>
      VrixObject.fromJson(jsonDecode(value) as Map<String, dynamic>);

  bool matchesTag(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return tags.any((tag) => tag.toLowerCase() == normalized);
  }

  void validate() {
    if (id.trim().isEmpty || displayName.trim().isEmpty || meshPath.trim().isEmpty) {
      throw const FormatException('Object id, display name and mesh path are required.');
    }
    if (id.length > 128 || displayName.length > 160) {
      throw const FormatException('Object identity fields exceed their supported length.');
    }
    if (tags.any((tag) => tag.trim().isEmpty || tag.length > 64)) {
      throw const FormatException('Semantic tags must be non-empty and at most 64 characters.');
    }
    physics.validate();
    transform.validate();
    _ensureJsonSafe(metadata);
  }
}

double _readNumber(dynamic value, double fallback) =>
    value == null ? fallback : (value as num).toDouble();

List<double> _readVector(
  dynamic value,
  int length,
  String name, {
  List<double> fallback = const [],
}) {
  if (value == null && fallback.isNotEmpty) return List.unmodifiable(fallback);
  if (value is! List) throw FormatException('$name must be a numeric list.');
  final result = value.map((item) => (item as num).toDouble()).toList();
  _validateVector(result, length, name);
  return List.unmodifiable(result);
}

void _validateVector(List<double> value, int length, String name) {
  if (value.length != length || value.any((item) => !item.isFinite)) {
    throw FormatException('$name must contain $length finite numbers.');
  }
}

void _ensureJsonSafe(Object? value, [String path = 'metadata']) {
  if (value == null || value is String || value is bool || value is num) return;
  if (value is List) {
    for (var i = 0; i < value.length; i++) {
      _ensureJsonSafe(value[i], '$path[$i]');
    }
    return;
  }
  if (value is Map<String, dynamic>) {
    for (final entry in value.entries) {
      if (entry.key.toLowerCase().contains('token') ||
          entry.key.toLowerCase().contains('password') ||
          entry.key.toLowerCase().contains('secret') ||
          entry.key.toLowerCase().contains('api_key')) {
        throw FormatException('Sensitive key is not allowed in $path.');
      }
      _ensureJsonSafe(entry.value, '$path.${entry.key}');
    }
    return;
  }
  throw FormatException('$path contains a non-JSON value.');
}
