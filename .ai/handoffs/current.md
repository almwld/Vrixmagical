# Current handoff

**Date:** 2026-11-20  
**Orchestrator / writer:** current task owner  
**Branch:** update this field at the start of each task  
**Status:** active multi-workstream closure

## Objective
Close the Jolt↔XPBD integration, connect RGB-D scan output to the physics runtime, stabilize AR anchors/depth, expose SplatKit/Vulkan controls and unify delegation/memory/skills.

## Current order
1. Finish PR #13 CI/review. Do not merge the coupling parent to main while impulse/contact integration gates remain open.
2. Finish PR #14 CI for the latest head and review the Kotlin conversion/depth calibration.
3. Reconcile scan runtime ownership with the persistent AR scene; keep the current isometric preview explicitly distinct from a live AR mesh.
4. Add a typed, per-view SplatKit Dart↔Kotlin bridge for load/frame/GPU events, stats, camera, quality, collider and tiled-world operations.
5. Add the shared AI delegation registry/playbooks/skills and run `python3 tool/validate_ai_handoff.py`.

## Non-negotiable checks
- Read the existing architecture before edits; smallest coherent changes; preserve public APIs.
- Never report a build/test/device run unless the actual CI/device evidence exists.
- No full multi-manifold or production-ready claim while the native contract is one contact per vertex.
- No ARCore/Vulkan runtime claim from emulator or CI alone.
- No secret/user image payload in logs or durable memory.
- Update this file and PROJECT_STATE.md when a workstream changes state.
