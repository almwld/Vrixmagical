# VRIX project state

**Last reconciled:** 2026-11-20  
**Canonical branch:** `main`  
**Reference device:** LG V60 ThinQ 5G (`LM-F100`)

## Verified architecture boundaries

- Flutter/Android application and a single ARCore session/camera owner.
- Jolt Physics 5.6 owns rigid-body world stepping and collisions; XPBD/FEM owns deformable vertices.
- RGB-D capture is sourced from one ARCore frame callback. The scanner persists RGB, masks, camera pose, CPU-image intrinsics, depth timestamps and confidence.
- Voxel reconstruction, GLB export and structured tetrahedralization exist. Tetrahedral solver vertices are object-local metres and preserve a separate world origin.
- SplatKit Android/Vulkan is pinned as an app dependency. The native renderer is hosted by a PlatformView; the new typed per-view Flutter bridge is in PR #16.
- Repository-wide AI delegation and durable memory are introduced by PR #15; Telekinesis-CV inherits the root protocol.

## Active PRs and exact-head evidence

- **PR #13 — Jolt↔XPBD and scan runtime:** `fix/xpbd-contact-ownership-arbitration`, head `36edce1dd483bd1a3e9b286785c2dcd23a536749`. Includes sensor-proxy overlap queries, deterministic per-vertex ownership, scan-to-runtime wiring, world-origin restoration and a Flutter isometric preview. Per-contact reaction impulses are kept separate to preserve torque couples. Run #308 passed native XPBD regression, formatting, Dart analysis and Flutter tests; Android debug APK was in progress at last check. The latest probe/normal telemetry is included in this head. Earlier run #278 passed the full artifact matrix before the interactive probe was added.
- **PR #14 — AR anchors/RGB-D:** `fix/ar-anchor-quaternion-conversion`, head `bafbdf88c89e7556f40cdf3527e7737d36bccde5`. Includes normalized x,y,z,w quaternion conversion, AnchorNode pose ownership, CPU-RGB-matched depth intrinsics with a scaling helper/test, and race-safe cloud-anchor pending callbacks. Run #288 passed Kotlin anchor/depth tests, Flutter analysis and Flutter tests; Android debug APK was in progress at last check.
- **PR #15 — unified AI delegation/memory/skills:** `feat/unified-ai-delegation-memory-skills`, head `ac7e024b70fe79d2065a8717e1e128d6a8777cf5`. Adds one orchestrator protocol, 7 skills, 6 playbooks, durable state/handoff files, AGENTS guidance and a registry validator. Run #298 passed the full CI/artifact pipeline including registry validator, Flutter tests, APKs, split APKs, AAB, native checks and artifact upload.
- **PR #16 — SplatKit/Vulkan bridge:** `feat/splatkit-vulkan-bridge`, head `f9a4e5436e45269175ad8c266a1944f8327dc3cd`. Adds a per-view MethodChannel, world/first-GPU-frame/failure events, stats, camera/quality/motion/collider controls, controller tests, and checks for libsplatkit.so plus 16 KiB ELF LOAD alignment in APK/AAB. Run #309 is validating a documentation-only status refresh. The immediately preceding exact code head passed run #294 end-to-end: Flutter tests, debug/release/split APKs, SplatKit native-library presence, 16 KiB ELF alignment, release AAB and artifact upload.
- **PR #7 — Jolt↔XPBD base coupling:** remains the integration parent. Do not merge to main until PR #13 is reconciled and the remaining acceptance gates below are satisfied.

These statuses are snapshots. Always fetch current PR head SHA and CI run before taking action.

## Remaining acceptance gates

1. PR #13 exact-head CI is green, including reaction-mapper and Jolt pure-torque tests. Add an end-to-end same-scene test with a real XPBD runtime and dynamic Jolt body when the host FFI test harness supports it.
2. Verify collision normal direction, contact begin/stay/end, body removal and actual equal/opposite force/torque on LM-F100.
3. Move scan-created soft-body ownership into the persistent scene owner and add a live deforming ARCore SceneView mesh. Current scan preview is an isometric Flutter projection and the scan screen still owns a local Jolt scene.
4. Finish exact-head CI for PR #14; validate anchor placement, tracking pause/resume, relocalization, cloud-anchor round-trip and RGB-D depth registration/occlusion on LM-F100.
5. Finish exact-head CI for PR #16; verify the pinned Maven beta.3 artifact exports all bridge symbols, libsplatkit.so is packaged in each shipped artifact and 16 KiB alignment checks pass. Exercise first GPU frame, Vulkan failure, pause/resume, collider loading and repeated view disposal on a physical device.
6. Add a directory-aware tiled-world import flow and expose capability/policy fallback diagnostics in the Splat UI.
7. Keep AI delegation as one orchestrator + registry-backed skills/playbooks + concise durable memory. No autonomous agent proliferation; update PROJECT_STATE and current handoff when PR/CI state changes.

## Evidence labels

- **Source implemented:** code exists in a branch.
- **Unit verified:** relevant automated tests passed.
- **Build verified:** exact-head APK/AAB and native packaging checks passed.
- **Device verified:** exercised on the named physical device.
- **Production accepted:** all relevant device, performance, lifecycle and safety gates passed.

Never collapse these labels into a single “done” state.
