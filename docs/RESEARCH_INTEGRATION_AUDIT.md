# Research Project Integration Audit

Baseline: `main` at `5c4bc3c792142da4f48b9c9fee710a96837188f6`.

This audit distinguishes reusable capabilities from standalone demos and source repositories. A directory being present is not evidence that its runtime is part of the Flutter app. Integration means a maintained app-owned implementation, explicit lifecycle/permission ownership, tests, and device validation.

## Integration target

The Flutter application remains the product shell and owns navigation, permissions, camera arbitration, AR session lifecycle, scene graph, persistence, and user-facing error handling. Research code is adopted through narrow interfaces; complete unrelated applications are not nested as second app shells.

## Inventory and decisions

| Repository / directory | Existing capability | Decision | Target |
|---|---|---|---|
| `Telekinesis-CV/` | EdgeSAM 3x ONNX encoder/decoder, point/box prompts, positive/negative corrections, candidate ranking, temporal selection, hand-aware rejection, mask cleanup, background reconstruction, two-hand transforms, throw/physics, hide/duplicate/restore | **High priority: port the inference and interaction capabilities**, not the Python/OpenCV desktop shell. Preserve model revision and SHA-256 provenance. | Android native ONNX Runtime bridge + Dart segmentation service; scene manipulation controller |
| `web-ar-hand-tracking/` | Worker-based MediaPipe inference, back-pressure, watchdog/recovery, scale-invariant gestures, convex-hull hand occluder, performance governor, FPS/latency instrumentation, 5 hand experiences | **High priority: port tested domain algorithms and reliability patterns**. Do not ship a browser/Three.js duplicate. | Shared hand tracking/gesture domain, hand depth occluder, adaptive quality controller |
| `portalble/` | Unity AR Foundation + MediaPipe hand interaction, bare-hand object manipulation, example prefabs/scenes and physics interaction | **Study and selectively port interaction concepts**. Do not embed the full Unity project or its large sample asset catalog in the Flutter APK. | AR interaction adapter and gesture-to-anchor/object manipulation |
| `arfoundation-samples/` | Broad Unity AR Foundation reference: plane/anchor, occlusion, depth, human body, image/object tracking, environment probes, meshing and sample renderers | **Reference implementation for missing AR capabilities**. Port only APIs/features supported by ARCore and the app's AR host; retain upstream attribution/license. | Native Android ARCore bridge for depth/occlusion, capability reporting and tests |
| `xr_sandbox/` | Three.js + Cannon-es rigid-body physics, collisions, GLB bodies, dragging/spawning and debug overlays | **High priority: port physics behavior and test scenarios**, not the browser app. Physics must use explicit collision proxies; Gaussian splats are not collision meshes. | Native/Flutter 3D physics adapter with fixed-step simulation and collider lifecycle |
| `splatkit/` | Native C++/Vulkan renderer, SPZ/LODSPLAT, LOD hierarchy, streaming tilesets, camera navigation, collider-aware walking, render policies and capability limits | **Keep the existing native Android integration; audit and expose the useful SDK features**. Current Flutter screen only imports a file and creates a PlatformView. Prioritize tilesets, collider loading, quality policy, navigation and lifecycle diagnostics where beta.3 exposes them. | Splat platform channel + Dart world/session controller |
| `Ar-projects/` | MediaPipe finger-count launcher and dual-hand galaxy/orb visual effects | **Adopt safe creative interaction ideas only**. Replace hard-coded website launching with in-app actions requiring explicit user configuration. | Optional gesture effects in the hand/scene experience |
| `playcanvas-vr-twa-demo/` | PlayCanvas/WebXR splat demonstration and sample PLY | **Reference/demo only**. Do not add a WebView or duplicate renderer to the core Android scene. | Evaluate only if it contributes a format/interaction not covered by SplatKit |
| Current Flutter `lib/` | ARCore/ARKit shell, hand mirror, MediaPipe still-frame analysis, interactive segmenter, SplatKit viewer | **Canonical product runtime**. Keep one camera/session owner and one scene/object identity model. | All adopted features integrate here |

## Important constraints discovered

- EdgeSAM is implemented in Python using OpenCV, NumPy and ONNX Runtime. Its encoder/decoder are not currently wired into Flutter. A correct port must preserve resize/padding/crop coordinate transforms, point/box prompts, positive/negative prompts, logits, candidate ranking and stale-request cancellation. Replacing this with a package declaration or a different segmenter is not equivalent.
- The EdgeSAM project pins model revision `e0564124628944e1622973d4e0f68158b46f035a` and SHA-256 digests in `Telekinesis-CV/segmentation.py`. Preserve provenance and verify digests before loading.
- The existing Flutter interactive cutout is still-image based and uses MediaPipe Interactive Segmenter. It must remain a working fallback while EdgeSAM is introduced behind a capability-aware interface.
- The browser hand tracker runs inference in a worker with one frame in flight, a watchdog and GPU-to-CPU fallback. The Flutter camera stream currently uses a busy flag and skips frames; port the reliability concepts without creating a second camera owner.
- The web hand occluder is a convex hull of hand landmarks that writes depth. This is a hand-only approximation, not general real-world occlusion. Real scene occlusion requires ARCore Depth API (or a supported depth image path) and correct depth texture registration.
- Portal-ble is a separate Unity 2021.3 Android project and explicitly relies on MediaPipe computer vision without a depth sensor. Its full project is not a suitable Flutter dependency.
- AR Foundation samples are Unity C# reference code, not directly importable into Flutter. Use Android ARCore APIs through a small native bridge rather than adding Unity as a second app runtime.
- XRSandbox physics is a browser Three.js/Cannon-es prototype. Its concepts are useful, but the production runtime needs fixed-step simulation, collider lifecycle, transform synchronization, pause/resume and bounded object counts.
- SplatKit's upstream README describes tileset streaming, collider-aware navigation and render policy, but the current app screen only copies a single SPZ/LODSPLAT and passes its path to a PlatformView. Confirm which methods exist in the pinned beta.3 artifact before exposing controls. Do not assume unreleased source APIs are present in Maven beta.3.
- A physical LG V60 ThinQ 5G (LM-F100) is the reference target. ARCore certification does not prove every API/device configuration works; Vulkan 1.1 and SplatKit runtime behavior still need an on-device probe.

## Integration sequence and acceptance gates

1. **Shared domain and reliability** — port normalized gesture math, pinch hysteresis/dwell, hand-loss reset, two-hand transform math, frame back-pressure/watchdog concepts, adaptive quality tiers and deterministic tests. Keep camera ownership in the existing feature.
2. **EdgeSAM advanced cutout** — add Android ONNX Runtime behind a Dart interface; port preprocessing/postprocessing and prompt/candidate logic; model digest verification; async cancellation/stale result rejection; preserve Interactive Segmenter fallback. Acceptance: golden coordinate/mask tests, model-load failure tests, latency/memory measurements on LM-F100.
3. **Real depth and occlusion** — inspect `flutter_reality` native ARCore implementation; add a narrow Android depth-image bridge if the plugin does not expose depth. Add capability detection and graceful fallback. Acceptance: depth confidence/validity handling, rotation/crop alignment tests, occlusion visual test on LM-F100.
4. **Physics and interaction** — select a supported native 3D physics engine after ABI/API and maintenance review. Build a scene-object/collider contract; synchronize at fixed timestep; support grab/release/throw, rigid-body collisions and material properties. Add soft-body only after stable rigid-body benchmarks.
5. **Capture and reconstruction** — create a separate capture pipeline (camera frames, timestamps, poses/SLAM, depth, point cloud, export). Use SplatKit only for rendering prepared worlds; it is not a reconstruction engine. Evaluate mobile capture feasibility and desktop preprocessing separately.
6. **Scene-aware voice and multimodal commands** — local speech recognition where feasible, parse into a constrained typed command schema, resolve only current scene object IDs, and require confirmation for destructive or external actions.
7. **SplatKit capability completion** — verify native beta.3 API, Vulkan capability query, renderer lifecycle, tileset/collider support and memory limits. Add explicit unsupported-state messaging and runtime diagnostics.
8. **Consolidation and cleanup** — after all adopted capabilities pass tests and the Flutter app owns their runtime, move non-runtime source projects into a clearly labelled `research/` archive or retain them with an inventory/license manifest. Do not delete original research or third-party source until license, provenance and feature parity are reviewed.

## Definition of done

A feature is not complete because its source was copied. It must have an app-owned integration, bounded resource lifecycle, tests for pure logic and failure paths, CI green, documented device/API requirements, and physical-device evidence for camera/AR/GPU behavior. No unverified runtime capability may be labelled production-ready.
