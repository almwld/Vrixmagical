import 'package:vector_math/vector_math_64.dart';

/// One per-vertex XPBD reaction sample at its original rigid-body contact point.
class SoftBodyReactionContact {
  const SoftBodyReactionContact({
    required this.rigidBodyId,
    required this.vertexIndex,
    required this.contactSlot,
    required this.worldPoint,
  });

  final String rigidBodyId;
  final int vertexIndex;
  final int contactSlot;
  final Vector3 worldPoint;
}

/// A point impulse that preserves the force and torque of one XPBD contact.
class SoftBodyReactionImpulse {
  const SoftBodyReactionImpulse({
    required this.rigidBodyId,
    required this.impulse,
    required this.worldPoint,
  });

  final String rigidBodyId;
  final Vector3 impulse;
  final Vector3 worldPoint;
}

/// Maps native per-vertex reaction forces to independent world-space impulses.
///
/// Contacts are deliberately not collapsed into one resultant impulse per
/// rigid body: two equal/opposite forces at different points can have zero net
/// linear impulse but a non-zero torque couple.
class SoftBodyReactionMapper {
  const SoftBodyReactionMapper._();

  static List<SoftBodyReactionImpulse> map({
    required List<double> packedForces,
    required Iterable<SoftBodyReactionContact> contacts,
    required Matrix4 worldTransform,
    required double deltaSeconds,
    required bool Function(String bodyId) isDynamicBody,
  }) {
    if (!deltaSeconds.isFinite || deltaSeconds < 0) {
      throw ArgumentError.value(deltaSeconds, 'deltaSeconds');
    }
    final worldOrigin = worldTransform.transform3(Vector3.zero());
    final result = <SoftBodyReactionImpulse>[];

    for (final contact in contacts) {
      if (contact.vertexIndex < 0) {
        throw RangeError.index(contact.vertexIndex, packedForces);
      }
      if (contact.contactSlot < 0 || contact.contactSlot >= 4) {
        throw RangeError.value(contact.contactSlot, 'contactSlot');
      }
      final offset = (contact.vertexIndex * 4 + contact.contactSlot) * 3;
      if (offset + 2 >= packedForces.length) {
        throw RangeError(
          'Reaction buffer does not contain vertex ' +
              contact.vertexIndex.toString() +
              '.',
        );
      }
      if (!isDynamicBody(contact.rigidBodyId)) continue;

      final localForce = Vector3(
        packedForces[offset],
        packedForces[offset + 1],
        packedForces[offset + 2],
      );
      if (!localForce.x.isFinite ||
          !localForce.y.isFinite ||
          !localForce.z.isFinite) {
        throw StateError('XPBD returned a non-finite reaction force.');
      }
      final worldForce =
          worldTransform.transform3(localForce) - worldOrigin;
      final impulse = worldForce * deltaSeconds;
      if (impulse.length2 <= 1e-14) continue;

      result.add(
        SoftBodyReactionImpulse(
          rigidBodyId: contact.rigidBodyId,
          impulse: impulse,
          worldPoint: Vector3.copy(contact.worldPoint),
        ),
      );
    }
    return result;
  }
}
