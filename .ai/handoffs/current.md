# Current handoff

**Date:** 2026-11-20  
**Orchestrator / writer:** current task owner  
**Canonical branch:** main  
**Status:** active cross-layer closure

## Objective
Close Jolt↔XPBD coupling, connect scan output to physics, stabilize AR anchors/depth, complete SplatKit/Vulkan host controls and maintain one shared AI delegation/memory system.

## Current exact-head work
1. **PR #13** — head 1dda4712de05c186dcfb6155f3ca34d85ea86154; run #278. Run #278 passed the complete artifact matrix, including the per-contact reaction mapper and Jolt pure-torque test. Physical same-scene/device acceptance remains open.
2. **PR #14** — head a2c7c785780f8b18a0463d0ec9db1acc9e326c0c; run #288 passed Kotlin anchor/depth tests, Flutter tests and analysis; Android debug build was active. Includes anchor quaternion, CPU RGB-D intrinsics scaling and race-safe pending cloud-anchor callbacks.
3. **PR #16** — head bcf25022ce95fbe22384cfb22e09a17757103c96; run #294. Flutter analysis and tests passed (including tiled-world directory import and Hi-Z policy controls); Android debug build was active. The earlier run #275 passed full APK/AAB/native/16 KiB checks before these additions.
4. **PR #15** — head 3fbd99fceccf4c2fb1eebb45df3f04c76e228309; run #287 passed full CI and artifact upload, including the registry validator. This current memory refresh triggers another validation run.

## Next actions
- Poll the exact CI runs above; fix failures on their own branches.
- Do not merge PR #13 into main; it is based on the PR #7 coupling branch and still needs same-scene integration/device acceptance.
- Do not claim live AR mesh rendering: the current scan screen uses a renderer-neutral isometric preview.
- Do not claim Vulkan device readiness from CI; wait for a physical device run.
- Update PROJECT_STATE.md and this handoff after every material state change.

## Acceptance gates
- Jolt/XPBD: actual force direction, per-contact torque, contact lifecycle and same-scene dynamic-body interaction.
- Scan: persistent scene ownership and live AR mesh renderer.
- AR: anchor lifecycle/relocalization and RGB-D alignment on LM-F100.
- SplatKit: exact beta.3 bridge compile, native library packaging, 16 KiB alignment, first GPU frame, stats and lifecycle on a physical Vulkan device.
- AI: one orchestrator, one writer per branch, bounded specialist delegation, validator passing, no secrets/raw reasoning in memory.
