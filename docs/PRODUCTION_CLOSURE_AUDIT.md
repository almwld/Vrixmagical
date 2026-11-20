# VRIX Magical — Production Closure Audit

Audit date: 2026-11-20  
Baseline: `main` at `fcb43e25ce7772d30211b76a94436b36e35a5be1`  
Purpose: establish an evidence-based closure plan without changing production code or claiming unverified capabilities.

## Verified repository state

- Default branch: `main`; repository is public and writable by the connected account.
- Latest commit message says the Jolt, XPBD and synchronized RGB-D work was integrated after native XPBD, Flutter analysis/tests, Android debug/release APK and AAB validation.
- The connector returned no commit status entries or PR-triggered workflow runs for the original baseline SHA. New PR workflow evidence is now available for #7, #9 and #10 as recorded above.
- Main contains Jolt rigid-body integration, synchronized RGB-D capture, voxel reconstruction/export and a native XPBD solver path.
- Main also contains source for a bidirectional Jolt↔XPBD coordinator on a separate branch; it is not yet part of main.
- Main's README is stale/inconsistent with newer scanning and XPBD documentation and must be reconciled only after the source/CI audit.

## Pull requests found

Open PR search returned:
- #7 — bidirectional Jolt ↔ XPBD soft-body coupling — remains open. CI run #254 passed, but an engineering review comment records a contact-identity/multi-contact correctness hold and missing coupling integration tests.
- #9 — Android launcher icon generation from canonical SVG — merged as `b9f8e3625a30ba3ebe811d63dc2b7d37e93ec053`; CI run #248 passed, including SVG-derived icon verification and Android debug/release APK/AAB builds.
- #10 — isolate AR startup from native Jolt initialization — merged as `40bf8d901d9645793ea82cc4f6e2ea82e2899c4e`; CI run #249 passed, including analysis, tests and Android debug/release APK/AAB builds.

The audit PR #11 itself remains a documentation-only draft. Historical PRs #1 and #6 were found closed/merged.

## Branch divergence from main

The following are comparison counts against main at audit time. Do not merge branches wholesale: several contain duplicated or superseded work.

| Branch | Ahead | Behind | Comparison |
|---|---:|---:|---|
| feat/jolt-xpbd-bidirectional-coupling | 10 | 0 | ahead |
| feature/physics-collision-core | 6 | 2 | diverged |
| feature/physics-scene-runtime | 6 | 2 | diverged |
| feature/production-jolt-physics | 73 | 1 | diverged |
| feature/real-object-scanning | 219 | 1 | diverged |
| fix/android-svg-launcher-icons | 6 | 0 | ahead |
| fix/ar-startup-isolate-jolt | 1 | 0 | ahead |
| integration/unify-research-projects | 15 | 3 | diverged |

## Capability truth table

| Capability | Current evidence | Closure gate |
|---|---|---|
| Jolt rigid-body engine | Source, tests and Android packaging checks are present | Re-run CI on current main; device startup, lifecycle, CCD, joints and performance |
| AR scene bridge | Source-level Jolt-to-AR transforms and sample prop path | Real-device scale/gravity/anchor calibration, tracked-plane updates, anchor-loss recovery |
| RGB-D scanning | Same-frame capture bridge, manifest v3, alignment and persistence code | Physical LG V60 capture evidence, depth support/registration, thermal/stability |
| Mesh reconstruction | Bounded voxel-derived surface and GLB export source/tests | Independent GLB viewer, real-scan quality/accuracy and collider validation |
| XPBD soft bodies | Native adapter, FEM path and CTest regression described in repository docs | Android ABI packaging, rendered deformation, device performance and lifecycle |
| Jolt↔XPBD coupling | Separate PR/branch adds contact coordinator | Merge only after CI, review, scene wiring and physical collision acceptance |
| Gaussian Splat / Vulkan | SplatKit Android integration source | arm64/Vulkan 1.1 device validation, lifecycle and memory/thermal profiling |
| EdgeSAM / SAM2 | Research/reference only | License, pinned model hash, Android ONNX runtime and device benchmarks |
| AR depth occlusion | ARCore capture depth data is present; rendering occlusion is not established | Depth-to-camera calibration and real-time occlusion validation |
| Fluids | No production runtime evidence | Remains out of current closure scope |
| Voice scene commands | Typed allow-listed command contract only | Local speech runtime, intent validation, confirmation gates and tests |
| AI Delegation in app | Agent guidance exists in research/SplatKit subtrees; no verified app-wide central orchestrator/Playbook runtime | Define app-level orchestrator, skill registry, playbook contract, shared tools, permission gates, persistence and tests |

## Ordered closure work

1. Establish authoritative main CI evidence: formatting, Flutter analysis, Dart tests, native CTest, Android debug/release/split APK and AAB; capture artifacts and logs.
2. Review PRs #7, #9 and #10 individually. Rebase or cherry-pick only the minimal valid changes; do not merge divergent branches wholesale.
3. Reconcile README and capability/status docs so each feature has one consistent state: implemented, CI-verified, device-verified, or not integrated.
4. Complete Jolt↔XPBD coupling in a dedicated integration scene, with deterministic contact lifetime, coordinate conversion, impulse sign/unit tests and safe teardown.
5. Close AR/scanning gaps: imported GLB placement, tracked-plane/anchor recovery, scan-to-GLB verification and physical-device capture evidence.
6. Validate SplatKit/Vulkan and Android lifecycle on supported hardware; record frame-time, memory and thermal measurements.
7. Implement app-wide AI Delegation only after defining the single orchestrator contract; reuse skills/playbooks/toolbox rather than spawning many independent agents. Enforce least privilege, approval for destructive actions, cancellation propagation, structured results and no automatic replay of side effects.
8. Run end-to-end regression and publish a release-readiness matrix. No capability is production-ready until its specific gates pass.

## Guardrails

- Preserve existing AR camera/session ownership and public Dart contracts.
- Keep source research projects intact; port only proven, licensed components.
- Never infer runtime support from source presence or CI green alone.
- Never claim physical-device validation without recorded device evidence.
- Keep changes small, independently committed, and tested before advancing.
