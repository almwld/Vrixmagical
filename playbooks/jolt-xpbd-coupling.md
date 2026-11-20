# Playbook: Jolt and XPBD

## Goal
Establish a stable two-way rigid/deformable coupling and connect scanned tetrahedral meshes.

## Steps
1. Inspect PhysicsSceneService, native XPBD contact contract, fixed-step owner and scan reconstruction.
2. Preserve object-local metres and a separate world-origin transform.
3. Use a non-resolving sensor/query proxy; refresh overlap point/normal each frame.
4. Apply contact policy per vertex and clear on separation, ownership change and disposal.
5. Convert reaction force into world impulse at contact position; verify torque and one-step feedback delay.
6. Wire scan output to one VrixSoftBodySceneRuntime; never create a second camera or simulation authority.
7. Add a dynamic Jolt integration test and a live surface renderer before production acceptance.

## Acceptance
Native XPBD regression, Jolt overlap/sensor tests, actual reaction impulse direction/magnitude, torque, multiple-body contact and device performance all pass.

## Explicit limits
One contact per vertex is not full manifold support. A convex proxy is approximate. A Flutter isometric preview is not a live AR mesh.
