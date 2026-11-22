# Playbook: Gaussian Splat and Vulkan

## Goal
Complete the Flutter host integration of the existing SplatKit Android/Vulkan renderer.

## Steps
1. Inspect the pinned SDK API, capability gates, renderer lifecycle and current PlatformView factory.
2. Add a typed per-view method/event channel; never use a global mutable renderer singleton.
3. Surface world-ready, first GPU frame, world failure and GPU failure distinctly.
4. Expose file/tiled-world loading, camera/orbit/focus, quality/render policy, collider and readStats.
5. Add a loading/error/status UI, stats polling that stops on pause/dispose and cancellation-safe requests.
6. Validate SPZ and LODSPLAT import, native library packaging, Vulkan capability fallback and resource teardown.
7. Run physical Adreno/Mali device tests; record FPS, GPU time, memory, temperature and long-session stability.

## Acceptance
A real first GPU frame is observed; failures are visible; no leaked views/threads; Vulkan 1.1 device acceptance passes. Do not treat file import or PlatformView creation as proof of rendering.
