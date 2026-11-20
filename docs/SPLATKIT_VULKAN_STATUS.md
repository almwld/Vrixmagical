# SplatKit / Vulkan integration status

**Pinned Android artifact:** `io.github.xget7:splatkit-android:0.1.0-beta.3`  
**Platform gate:** Android API 29+, arm64-v8a, Vulkan 1.1.  
**Owner:** SplatKit native C++/Vulkan renderer; Flutter owns the view, controls and lifecycle.

## Implemented in this change

- One SplatSurfaceView per Flutter PlatformView, with a MethodChannel scoped to its view ID; no global mutable renderer channel.
- Native lifecycle is forwarded through the existing view registry on activity resume/pause and view disposal.
- Buffered events distinguish world upload, first completed GPU frame, GPU failure, world failure, collider ready and collider failure. Events are queued until Dart attaches, so early load results are not silently lost.
- Typed Dart controller exposes renderer stats (FPS, frame/GPU/sort times, loaded/drawn splats, SH degree), camera pose, camera orbit/dolly/focus/look, gyroscope motion, quality presets, render scale, SH degree, frame cap, render policy, collider loading, tiled-world loading and benchmark capture.
- The viewer UI now reports the first GPU frame separately from world upload, displays GPU diagnostics/stats, offers quality and motion controls, orbit/zoom controls, and imports a GLB collider.

## Important semantics

- `worldReady` means decoded/uploaded; it is **not** proof that Vulkan completed a frame.
- `worldFrameReady` means the GPU completed the first frame; it does not guarantee display scanout.
- A Gaussian Splat world is visual geometry. It is not automatically a Jolt collider. Load a prepared GLB collider explicitly.
- Tiled-world loading is available through the controller API; a complete directory-aware picker/copy workflow remains pending.
- A false `isAvailable` immediately after PlatformView creation can mean Vulkan is still initializing. Wait for first-frame or explicit GPU-failure events.

## Remaining acceptance gates

1. Run the Android build against the exact Maven beta.3 artifact and verify every bridge symbol exists in that artifact.
2. Verify packaged SplatKit native libraries and 16 KB page/ZIP alignment for every shipped ABI.
3. Exercise SPZ and LODSPLAT imports, collider loading, pause/resume, repeated view creation/disposal and GPU/world failure paths.
4. Add a directory-aware tiled-world import workflow and surface device capability/policy fallbacks in the UI.
5. Test on a physical Vulkan 1.1 device (including the target LG V60 where supported): first frame, sustained FPS/GPU time, memory, thermal throttling, background/resume and long-session stability.

CI compilation and emulator success do not establish Vulkan presentation or physical-device performance.
