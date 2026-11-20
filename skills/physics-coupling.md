# Skill: Jolt ↔ XPBD coupling

## Trigger
Rigid/deformable contact, soft-body scan runtime, reaction force, impulse or contact lifecycle work.

## Inputs
Tetrahedral mesh in object-local metres, world transform, Jolt scene owner, fixed-step contract, material parameters.

## Steps
1. Keep Jolt as rigid-world owner and XPBD as deformable-state owner.
2. Define the normal direction explicitly: rigid surface toward deformable free space.
3. Prevent double response. A sensor/query proxy must not also be resolved by Jolt.
4. Map each overlap to a valid local contact point and nearest deformable vertex/face.
5. Manage contact ownership and removal deterministically; clear native constraints on end/disposal.
6. Convert XPBD reaction force to world impulse at the correct contact point; preserve torque arm.
7. Test sensor response, contact normal, owner arbitration, force sign/magnitude, multiple rigid bodies, removal and bounded stepping.

## Outputs
Adapter changes, native/Dart tests, contact limitations and device acceptance plan.

## Validation
The current native contract stores one contact per vertex. Never claim full manifold support. Unit tests are not proof of equal/opposite Jolt response; require an integration test with a dynamic rigid body.
