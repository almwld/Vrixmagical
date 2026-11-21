# VRIX Interaction Tick and Guided-Cavity Interaction

## Status

This document is the implementation contract for the next interaction-runtime increment. It is not a claim that cavity traversal, custom collision filtering, IK coupling, or GPU clipping are already implemented.

## Runtime ownership

- `PhysicsSceneService` owns the Jolt world and rigid-body lifetime.
- `VrixSoftBodySceneRuntime` owns the XPBD body, coupled contact adapter, and renderer-neutral surface snapshots.
- A future `VrixInteractionRuntime` coordinates input, character targets, guided paths, physics, and render snapshots. It must not own or duplicate either solver.
- The renderer consumes immutable snapshots and never advances physics.

## Fixed-step tick pipeline

1. **Collect inputs**: latch one timestamped `MotionFrame`, tracked joints, AR anchors, and interaction commands. Reject stale, non-finite, or out-of-order samples.
2. **Resolve targets**: convert inputs into world-space IK targets and optional guide-path targets. Clamp joint limits before sending targets to the character runtime.
3. **Advance rigid world**: feed accumulated XPBD reaction impulses from the previous soft-body step into Jolt, then advance Jolt by bounded fixed substeps.
4. **Refresh contacts**: query current Jolt contact/overlap geometry, convert points and normals into XPBD-local coordinates, and deterministically assign one contact owner per XPBD vertex (current native ABI limitation).
5. **Solve deformables**: advance XPBD using the same fixed-step clock. Preserve volume constraints and clear multipliers/reactions at the correct step boundary.
6. **Queue feedback**: map each XPBD reaction sample to a world-space impulse at its original contact point. Queue it for the next Jolt step; never mutate Jolt while draining its event buffers.
7. **Publish render state**: publish immutable positions, velocities, topology, transforms, and frame number. The renderer updates dynamic buffers/normals at its own bounded upload cadence.

The accumulator must cap catch-up work. If the frame budget is exceeded, drop excess accumulated time rather than running an unbounded spiral of death. Physics time and render time remain separate.

## Guided cavity / channel model

A traversable cavity is geometry plus a constrained interaction path, not a global collision disable.

A future `GuidedPathDefinition` must contain:

- Stable path and host-mesh identifiers.
- A local-space centreline (polyline or spline) with a well-defined tangent at every sample.
- Entry and exit intervals, permitted direction, and a finite travel range.
- A conservative radius/clearance profile along the path.
- Explicit inner-wall collision geometry or a validated cavity boundary.
- Allowed interaction body IDs / collision groups and a narrowly scoped pair-filter policy.
- Optional render-only occlusion metadata; physical collision geometry remains authoritative.

A future `GuidedPathState` must contain the projected path parameter, closest point, tangent, signed lateral error, entry/inside/exit state, and a monotonically increasing sample timestamp.

### Collision rules

- Keep ordinary world collisions enabled.
- Permit only the explicitly registered body/path pair to use guide or sliding constraints.
- Keep the cavity wall as a real collider; a sensor is for state detection, not a substitute for wall collision.
- Reject traversal if the host mesh has no validated interior channel or if clearance is insufficient.
- Use continuous collision detection or swept tests for fast movers to prevent tunnelling.
- On exit, disable guide constraints and restore the normal collision policy atomically.
- Never disable all collisions for a body as a shortcut.

### Deformation and rendering

Contact forces and path constraints may drive local XPBD boundary constraints only after coordinate frames and force ownership are explicit. Volume preservation remains active. Render clipping is optional visual assistance; real inner-wall geometry and depth occlusion are preferred. A shader mask must not be used to conceal invalid physics or missing cavity geometry.

## Acceptance tests

1. Fixed-step determinism: identical timestamped inputs produce equivalent solver states within tolerance.
2. Contact lifecycle: begin, persist, separate, and re-contact without stale multipliers or reaction impulses.
3. Two-way coupling: a non-zero XPBD reaction is applied to a dynamic Jolt body at its contact point; measure it across the full contact interval, not only the final frame.
4. Guided path projection: centreline projection, tangent continuity, clearance checks, and entry/inside/exit transitions.
5. Pair filtering: only the registered path pair receives guide behavior; unrelated environment collisions remain active.
6. Safety boundaries: out-of-channel motion collides with the actual wall, high-speed motion does not tunnel, and insufficient cavity geometry rejects activation.
7. Render synchronization: immutable snapshots are monotonic and topology-stable; dynamic mesh updates do not advance physics.
8. Lifecycle: disposal clears path/contact constraints and native resources exactly once.

## Current implementation gaps

- `PhysicsSceneService` currently initializes every row of `JJ_WorldSettings.collides` to `0xFFFF`; its bodies use broad static / moving / sensor layers. The adapter does not expose a safe, scoped per-body pair-filter operation.
- The app declares `just_jolt: ^0.2.0` and this branch does not track `pubspec.lock`. Inspection of upstream `release/0.2.0` shows that Jolt itself contains `GroupFilterTable`, and `joltc` already exports `JPH_GroupFilterTable_Create`, `DisableCollision`, `EnableCollision`, and `IsCollisionEnabled`, as well as `JPH_CollisionGroup` and body-interface collision-group get/set functions. The missing link is the higher-level `jj` world/body-handle facade used by `PhysicsSceneService`: `jj.h` / `jj_capi.cpp` expose world collision grids and body layers but do not expose a world-owned filter-table registry or a safe `jj_body_set_collision_group` operation. The generated Dart bindings also omit the `JPH_GroupFilterTable_*` entry points, so calling those raw functions from the app would bypass the adapter's world/body handle validation and lifetime rules. A correct extension belongs in the `jj` facade: own each table in its `JjWorld`, resolve and validate both body handles under the existing registry lock, assign matching group IDs and distinct subgroup IDs only to the explicitly registered pair, and restore the bodies' prior collision groups before releasing the table. Jolt's `GroupFilterTable` semantics make bodies with different group IDs collide, and bodies with the invalid/default group collide, so unrelated environment bodies can retain normal collisions. This still requires native regression tests for the allowed pair, unrelated environment contacts, same-subgroup exclusion, body/world disposal, and filter reference lifetime before enabling it in the app.
- Before guided traversal can alter collisions, add a native bridge that owns explicit pair registrations (or a dedicated Jolt group-filter implementation), validates both body handles belong to the same world, and restores the previous policy on exit/disposal. Preserve ordinary world collisions for all unregistered pairs. Add native tests proving an allowed guide pair is filtered while a third-party environment body still collides.
- The current soft-body contact ABI stores one contact per vertex. Multi-contact manifolds and barycentric surface contacts are future work.
- The current coupled adapter uses a convex proxy approximation. It is not an exact deformable-vs-triangle-mesh narrowphase.
- IK target solving is not yet part of the coupled runtime tick.
- Cavity mesh validation, guide-path constraints, shader clipping, and on-device traversal tests are not yet implemented.

These gaps must remain visible in capability reporting until their acceptance tests pass.
