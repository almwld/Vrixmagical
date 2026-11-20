# VRIX Interaction Runtime Contracts

## Status and compatibility

This document freezes the cross-layer data contracts for the next VRIX interaction increment. It is an interface specification, not a claim that every producer or consumer is implemented. Existing APIs remain authoritative until an adapter is migrated and its tests pass.

### Shared invariants

- Coordinates are right-handed world or explicitly named object-local metres; rotations are radians and unit quaternions.
- Every sample carries a monotonic timestamp and sequence/revision. Consumers reject non-finite values, stale samples, and out-of-order updates.
- Data crossing a runtime boundary is immutable (defensive copies for vector and collection values).
- Physics and XPBD advance only on the fixed simulation clock. Rendering consumes snapshots and never advances a solver.
- Ownership remains singular: PhysicsSceneService owns the Jolt world; VrixSoftBodySceneRuntime owns XPBD state; the future VrixInteractionRuntime orchestrates but does not duplicate either solver.

## Five canonical contracts

### 1. PoseDefinition — authored character pose

Purpose: describe an authored or target pose without owning a live skeleton or solver.

Required data:
- stable pose ID and skeleton/rig ID;
- rig revision or skeleton signature, so a pose cannot silently bind to an incompatible rig;
- named joint transforms in rig-local space (translation, unit quaternion, optional scale);
- per-joint limits (translation/rotation bounds and enabled degrees of freedom);
- named anchors (position and orientation) for hands, feet, contact points, and sockets;
- optional blend tags/weights and transition duration.

Validation: all transforms finite; quaternions normalized within tolerance; joint names unique; limits ordered and compatible with the rig; anchor names unique. Missing required joints fail binding explicitly rather than being silently remapped.

### 2. MotionFrame — timestamped motion intent/state

Purpose: transport one coherent motion sample through the fixed-step interaction pipeline.

Required data:
- monotonic frame sequence and capture timestamp;
- source clock and validity/confidence;
- root/world transform;
- joint pose samples or target transforms keyed by stable joint ID;
- linear and angular velocity where available;
- interaction phase and blend weights;
- optional beat/audio phase metadata (advisory, never a substitute for simulation time).

Validation: reject non-finite transforms/velocities, duplicate joint IDs, confidence outside [0,1], and timestamps older than the last accepted frame. Interpolate between valid samples; do not extrapolate beyond a bounded prediction horizon.

### 3. TouchInput — measured contact observation

Purpose: represent a tracked or simulated contact independently of the input provider.

Required data:
- stable contact ID, sequence, timestamp, and source (MediaPipe, AR hit-test, controller, or physics);
- source and target entity/anchor IDs;
- world-space contact position and unit normal;
- penetration/contact depth (metres; sign convention documented by producer);
- tangential velocity (m/s), optional normal velocity, pressure/force estimate, and confidence;
- coordinate-frame identifier and tracking status.

Validation: finite values, normalized normal, confidence in [0,1], non-negative pressure, monotonic sample time. Unknown or stale coordinate frames are rejected. A tracking estimate is not treated as a measured force.

### 4. DeformationState — immutable XPBD/render snapshot

Purpose: publish the result of one completed deformable simulation step.

Required data:
- body ID, simulation sequence/time, and topology revision;
- object/world transform and coordinate-space declaration;
- vertex positions and velocities; surface normals when available;
- optional strain/volume error and contact/reaction summaries;
- material/deformation channels needed by the renderer (roughness, normal/detail weights, etc.).

Validation: topology indices and buffer lengths match the referenced mesh revision; all numeric values finite; sequence monotonic. Buffers are immutable snapshots or explicitly leased buffers whose lifetime extends through upload. Filament must not mutate solver-owned memory.

### 5. GuidedPathDefinition — authored constrained path

Purpose: describe a valid guide path while preserving physical wall collision.

Canonical data:
- stable path ID, host mesh ID, and host transform/revision;
- local-space centreline control points and a finite clearance-radius profile;
- entry/exit tolerances, permitted direction, and finite progress range;
- allowed moving-body/host-body pair registration and collision-policy token;
- validated inner-wall/cavity geometry reference and optional render-only occlusion metadata.

Validation: at least two finite points; no zero-length segments; positive finite clearances; valid host mesh/revision; path clearance must exceed the moving body's radius plus configured safety margin. A path without validated cavity/wall geometry cannot enable traversal. The current `GuidedPathDefinition` model already covers centreline, clearance, direction and entry/exit classification; host identity, pair registration, and wall-geometry validation remain explicit integration work.

## Fixed-step ownership and ordering

1. Latch one MotionFrame and TouchInput batch; validate sequence, timestamp, confidence and coordinate frames.
2. Resolve PoseDefinition against the active rig and produce bounded IK targets.
3. Apply queued collision-policy changes at the world boundary, never during PhysicsSystem::Update.
4. Advance Jolt by bounded fixed substeps.
5. Resolve current contact observations and map them into XPBD-local coordinates.
6. Advance XPBD with the same simulation clock; preserve volume constraints.
7. Queue reaction impulses for the next Jolt boundary; do not mutate Jolt while draining event callbacks.
8. Publish immutable DeformationState.
9. Render/upload snapshots independently; do not advance physics from the render callback.

## Collision filter bridge invariants

- A `GroupFilterTable` is owned by exactly one `JjWorld` and remains alive until every body referencing it has been restored or destroyed.
- Jolt's `GroupFilterTable::CanCollide` semantics are part of the contract: different GroupIDs collide; equal GroupIDs with different `GroupFilter*` pointers do not collide; equal GroupIDs and equal filter pointers defer to SubGroupIDs and the table. Equal SubGroupIDs never collide.
- The pair bridge therefore assigns both target bodies the same bridge-owned GroupID and the same table pointer, with distinct SubGroupIDs (0 and 1). The table has exactly two subgroups. The bridge must reserve a GroupID not currently used by any body in the world; a collision with an existing GroupID could suppress an unrelated body's collision if its filter pointer differs.
- The bridge must reject or explicitly serialize overlapping active pair leases that would require one body to hold multiple temporary CollisionGroups. The initial ABI should reject a second active lease for either already-leased body rather than silently overwrite its saved state.
- Save each complete prior `CollisionGroup` (filter pointer, GroupID, SubGroupID) and retain a `Ref<GroupFilter>` for any non-null prior filter while that state is saved. `CollisionGroup` itself stores a raw filter pointer; copying the value alone does not keep that filter alive.
- Every C API operation holds the existing registry mutex; this serializes it against `jj_world_step` and world/body teardown. No filter mutation is allowed from a Jolt worker callback.
- Resolve both body handles and verify same-world ownership before reading or changing either body's group.
- Restore the exact saved group before releasing the pair's table reference on reset, pair release, body teardown, and world teardown. Body destruction must release its pair lease and restore the surviving partner before the destroyed body's storage is reclaimed.
- Only the registered pair is assigned the bridge GroupID/table. Unregistered bodies keep their prior groups; default/invalid-group environment bodies continue to collide normally.
- After changing either body's group or the table entry, call `BodyInterface::InvalidateContactCache` for both bodies and activate eligible bodies through `ActivateBodies`. The next fixed step must verify the expected contact transition; a broad-phase rebuild alone is not a substitute.
- Group/table destruction is idempotent and generation-checked; stale handles are harmless. The table must not be released while any body's CollisionGroup still contains its pointer.

## Ten-stage execution and acceptance gates

1. **Close CI #386 regression** — validate the workflow correction on #387; fix only the failing step; require analyze, unit/widget tests and package tests to pass.
2. **Prove native just-jolt build** — build the vendored Jolt 5.6.0/joltc/jj Android native targets; verify debug and release artifacts contain the expected ABI libraries. Do not infer success from source presence.
3. **Land the jj collision-group ABI** — add world-owned, generation-checked group handles and body assignment/reset APIs using the actual Jolt CollisionGroup/GroupFilterTable types.
4. **Prove collision isolation and lifetime** — native tests for one filtered pair, third-body/environment collision, original-group restoration, sleeping-body wake/cache invalidation, invalid/cross-world handles, body-first/world-first teardown, repeated create/destroy and no stale filter references.
5. **Freeze and test the five Dart contracts** — immutable models, validation, serialization/versioning where persisted, and unit tests for malformed/stale/out-of-order samples.
6. **Build VrixInteractionRuntime state machine** — IDLE → ANTICIPATION → APPROACH → CONTACT → ACTIVE → TRANSITION → RECOVERY; fixed-step orchestration only, with bounded interpolation and deterministic transitions.
7. **Connect skeleton/IK and XPBD** — rig signature checks, joint limits, anchor/socket handoff, contact ownership, volume preservation and two-way reaction tests.
8. **Connect DeformationState to Filament** — stable topology revisions, dynamic vertex/normal uploads, PBR channels and lifecycle-safe buffer ownership.
9. **Integrate MediaPipe and ARCore** — timestamp synchronization, confidence/staleness handling, world-anchor conversion, tracking-loss recovery and privacy-safe processing.
10. **Profile LG V60 and LG Wing** — measure frame-time percentiles, physics/IK/XPBD cost, memory, thermal throttling, battery and tracking latency in repeatable scenes. Record actual device/OS/build/config and baseline; 60 FPS is a target, not a pass until measured.


### Native handle-layout constraint discovered during implementation review

The current opaque object handle layout reserves exactly two type bits in `objectTag` (generation at bit 18, type at bits 16–17, world slot in the low 16 bits). The existing values 1, 2 and 3 are already assigned to bodies, joints and characters. A collision-pair handle must **not** be introduced as type 4 without redesigning the encoding: that value would spill into the generation field and could alias or invalidate unrelated handles.

Before adding the pair ABI, choose and test one explicit representation:
- allocate a collision-pair registry in the world and use a deliberately reserved type value only if the full `findOwner`/tag validation path proves it cannot alias an existing object kind; or
- revise the object-tag bit allocation for every object kind together, with regression tests proving old/stale/cross-world handles are rejected consistently.

The preferred minimal change is to avoid changing the public encoding for existing body/joint/character handles. The pair registry must still use generation/sequence checks and remain world-owned. Do not assume the unused numeric value zero is safe until `findOwner`, Dart-side handle validation, and all tag consumers have been inspected.

This is a pre-implementation safety gate, not evidence that the collision-pair ABI exists.

No stage is considered complete merely because code or a build artifact exists; each stage closes only when its acceptance gate is recorded.
