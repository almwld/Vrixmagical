# Skill: SplatKit and Vulkan

## Trigger
Gaussian Splat rendering, SPZ/LODSPLAT import, Vulkan rendering, tilesets, camera controls or GPU diagnostics.

## Inputs
Pinned SplatKit version/source, Android API/ABI, world path, view lifecycle, GPU capability report.

## Steps
1. Use the existing SplatKit SDK; do not create a second Vulkan renderer.
2. Keep one SplatSurfaceView per platform view and forward resume/pause/release.
3. Distinguish world decoded/uploaded, GPU frame completed, GPU failure and world failure.
4. Prefer file-backed loading for large worlds; support prepared SPZ/LODSPLAT and tiled worlds.
5. Expose typed per-view controls for camera, quality, render policy, collider and stats.
6. Respect API 29+, arm64 and Vulkan 1.1/subgroup/memory capability gates; fail clearly when unsupported.
7. Keep Gaussian splats visual-only; collision requires an explicit prepared mesh/collider.

## Outputs
Typed Flutter/Kotlin bridge, status/stats UI, tests and device validation report.

## Validation
Check packaged native libraries and 16 KB alignment. Run on a physical Vulkan device; emulator/CI cannot prove GPU presentation, memory stability or thermal performance.
