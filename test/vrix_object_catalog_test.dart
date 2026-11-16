import 'package:flutter_test/flutter_test.dart';
import 'package:virxmagical/domain/vrix_object.dart';
import 'package:virxmagical/services/object_library_catalog.dart';

void main() {
  group('VrixObject identity', () {
    VrixObject sample() => VrixObject(
          id: 'chair-01',
          source: ObjectSource.library,
          displayName: 'Chair',
          meshPath: 'models/chair.glb',
          physics: const PhysicsProfile(
            mass: 5,
            collider: ColliderShape.box,
            halfExtents: [0.25, 0.45, 0.25],
          ),
          tags: const ['chair', 'furniture', 'movable'],
          metadata: const {'license': 'CC0', 'source': 'curated-library'},
        );

    test('round-trips every identity field through JSON', () {
      final original = sample();
      final restored = VrixObject.decode(original.encode());

      expect(restored.id, original.id);
      expect(restored.source, ObjectSource.library);
      expect(restored.physics.mass, 5);
      expect(restored.physics.collider, ColliderShape.box);
      expect(restored.tags, contains('furniture'));
      expect(restored.transform.position, [0, 0, 0]);
      expect(restored.metadata['license'], 'CC0');
    });

    test('semantic tags are case-insensitive and exact', () {
      final object = sample();
      expect(object.matchesTag('CHAIR'), isTrue);
      expect(object.matchesTag('furn'), isFalse);
      expect(object.matchesTag('  '), isFalse);
    });

    test('rejects invalid identity, transform and physical ranges', () {
      expect(
        () => VrixObject(
          id: '',
          source: ObjectSource.captured,
          displayName: 'Desk',
          meshPath: 'desk.glb',
          physics: const PhysicsProfile(),
          tags: const [],
        ),
        throwsFormatException,
      );
      expect(
        () => VrixTransform(scale: const [1, 0, 1]).validate(),
        throwsFormatException,
      );
      expect(
        () => PhysicsProfile(friction: 1.2).validate(),
        throwsFormatException,
      );
    });

    test('refuses credential-like metadata keys', () {
      expect(
        () => VrixObject(
          id: 'generated-1',
          source: ObjectSource.generated,
          displayName: 'Generated object',
          meshPath: 'generated.glb',
          physics: const PhysicsProfile(),
          tags: const ['generated'],
          metadata: const {'api_key': 'must-not-be-stored'},
        ),
        throwsFormatException,
      );
    });
  });

  group('ObjectLibraryCatalog', () {
    const manifest = '''
    {
      "schemaVersion": 1,
      "assets": [
        {
          "category": "furniture",
          "license": "CC0",
          "sourceName": "Quaternius",
          "object": {
            "schemaVersion": 1,
            "id": "chair-01",
            "source": "library",
            "displayName": "Chair",
            "meshPath": "models/chair.glb",
            "physics": {"mass": 5, "collider": "box"},
            "tags": ["chair", "furniture"],
            "transform": {},
            "metadata": {}
          }
        }
      ]
    }
    ''';

    test('parses, filters and searches a license-aware catalog', () {
      final catalog = ObjectLibraryCatalog.decode(manifest);
      expect(catalog.assets, hasLength(1));
      expect(catalog.search(category: 'FURNITURE'), hasLength(1));
      expect(catalog.search(query: 'chair').single.license, 'CC0');
      expect(catalog.search(query: 'vehicle'), isEmpty);
    });

    test('rejects duplicate ids, unsafe paths and unknown schema versions', () {
      final duplicate = manifest.replaceFirst(
        '"id": "chair-01",',
        '"id": "chair-01",',
      ).replaceFirst(
        '"id": "chair-01",',
        '"id": "chair-02",',
      );
      // The one-entry manifest remains valid; duplicate detection is covered
      // with a duplicated entry in a separate minimal payload.
      expect(() => ObjectLibraryCatalog.decode('{"schemaVersion":2}'),
          throwsFormatException);
      final unsafe = manifest.replaceFirst('models/chair.glb', '../chair.glb');
      expect(() => ObjectLibraryCatalog.decode(unsafe), throwsFormatException);
      final duplicatePayload = manifest.replaceFirst(
        '"assets": [',
        '"assets": [',
      ).replaceFirst(
        '        }\n      ]',
        '        },\n        {\n          "category":"furniture",\n          "license":"CC0",\n          "sourceName":"Kenney",\n          "object": {"id":"chair-01","source":"library","displayName":"Chair 2","meshPath":"models/chair2.glb","physics":{},"tags":[],"transform":{},"metadata":{}}\n        }\n      ]',
      );
      expect(() => ObjectLibraryCatalog.decode(duplicatePayload),
          throwsFormatException);
      expect(duplicate, isNotEmpty);
    });
  });
}
