# VRIX project state

**Last reconciled:** 2026-11-20  
**Canonical branch:** `main`  
**Reference device:** LG V60 ThinQ 5G (`LM-F100`)

## Verified implementation boundaries

- Flutter/Android application and ARCore session owner are integrated in source.
- Jolt Physics 5.6 is the rigid-body authority. XPBD/FEM is a separate native deformable solver.
- RGB-D capture is sourced from one ARCore frame callback. The scanner persists RGB, masks, camera pose, stream intrinsics, depth timestamps and confidence.
- Voxel reconstruction, GLB export and structured tetrahedralization exist; they are conservative previews, not production photogrammetry or quality-optimized tetrahedral meshing.
- SplatKit Android/Vulkan is vendored as an app dependency and exposed through a native PlatformView. Current Flutter UI imports a single SPZ/LODSPLAT world; advanced camera, policy, stats and tiled-world APIs are not yet surfaced in Dart.
- AI delegation was previously project-local under `Telekinesis-CV/AI_TEAM.md`; this branch introduces the repository-wide protocol and registry.

## Active engineering work at last check

- **PR #13 — Jolt↔XPBD and scan runtime:** branch `fix/xpbd-contact-ownership-arbitration`, head `2318160be36dd84a80c8ba8aa5a8254ef93791ae`. Sensor-proxy overlap querying, deterministic per-vertex ownership, reaction impulse path and scan-screen runtime/preview are implemented in source. Workflow run #268 had passed native XPBD regression, formatting and analysis; Flutter tests passed; Android debug build was in progress. Full build and physical-device acceptance were not yet verified.
- **PR #14 — AR anchor/RGB-D calibration:** branch `fix/ar-anchor-quaternion-conversion`, head `6a287c37daa9c5616fa8f90a81eb77dec4808633`. Full ARCore quaternion conversion, AnchorNode pose ownership and CPU-RGB-matched depth intrinsics are implemented. The earlier CI attempt was cancelled after a branch update; a fresh run for this exact head was still pending.
- **PR #7 — Jolt↔XPBD base coupling:** remains the integration parent and must not be merged to main until its dependent fix and acceptance gates are reconciled.

These are historical snapshots for this handoff; re-check GitHub before making merge decisions.

## Open acceptance gates

1. Complete PR #13 CI and review the sensor overlap, normal orientation, reaction impulse magnitude/direction and torque path.
2. Add an integration test with a dynamic Jolt body and an XPBD deformable body in the same scene; prove equal/opposite response and contact-end cleanup.
3. Move the scan-created runtime into the intended persistent scene owner and provide a live deforming AR renderer; the current preview is a Flutter isometric projection, not a SceneView mesh.
4. Validate anchor placement, relocalization, cloud-anchor round-trip and RGB-D registration/occlusion on LM-F100.
5. Surface SplatKit world-ready/frame-ready/GPU failure events, stats, camera/navigation, quality policy, collider and tiled-world APIs through a controlled Dart bridge; test Vulkan 1.1 capability fallback and device lifecycle.
6. Complete physical-device Vulkan rendering/performance/memory/thermal acceptance; CI and emulator builds are insufficient.
7. Keep AI delegation as one orchestrator + registry-backed playbooks/skills + concise durable memory; do not create many independent autonomous agents.
