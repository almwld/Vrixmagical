# VirxMagical — Digital Reality Engine

VirxMagical is an Android-first Flutter application for interactive digital representations of physical objects. The digital layer can be moved and transformed while the real source object remains unchanged.

## Implemented application paths

- Arabic-first Flutter app shell and navigation.
- **AR scene:** native ARCore/ARKit session through `flutter_reality`, horizontal/vertical plane detection, tap hit-testing, anchors, GLB placement, drag/rotate and removal.
- **3D physics:** standalone Jolt Physics 5.6 native runtime through `just_jolt`; static/dynamic rigid bodies, box/sphere/capsule/convex-hull/static-triangle-mesh colliders, continuous collision mode, collision layers, sensors, buffered contact events, ray queries and six joint families.
- **Physics-to-AR bridge:** fixed-step Jolt simulation, batch active-body transform reads, world-to-anchor-local pose conversion, 30 Hz thresholded AR transform writes, manual interaction hand-off and explicit native teardown.
- **Hand mirror:** camera preview plus Google's MediaPipe Hand Landmarker in live-stream mode. A pinch grabs and moves a digital overlay; the physical source object is never modified.
- **Scene analysis:** on-device MediaPipe Object Detector and Image Segmenter on a captured frame.
- **Automated tests:** physics lifecycle/input validation, rigid-body contact/raycast behavior and existing hand-interaction behavior.

## Physics architecture and production verification boundary

Jolt owns rigid-body simulation; `flutter_reality`/ARCore owns camera tracking, anchors and visible GLB nodes. The native engine is compiled from Jolt Physics 5.6 through the standalone `just_jolt` FFI package. This avoids coupling the physics runtime to a second renderer or a Filament PlatformView.

The app adapter exposes static/dynamic/kinematic bodies, box/sphere/capsule/convex-hull/static-triangle-mesh colliders, sensors, collision-layer masks, contact/sensor/activation event streams, raycast/overlap/shape-cast queries, forces/impulses, continuous collision mode, and fixed/point/hinge/slider/distance/six-DOF joints. AR objects are synchronized using batched reads of awake bodies and bodies that just went to sleep. Drag/rotate hand-off uses Jolt's body interface to teleport a body while preserving its attached constraint graph; velocity is reset by default.

The current AR placement sample uses a finite static box for the tapped surface and a manually approximated dynamic box for the sample Duck asset. The service also supports convex-hull and static triangle-mesh cooking, but automatic GLB mesh extraction/collider generation and per-asset collider metadata are not yet wired. Moving tracked-plane updates and anchor-loss recovery still need implementation. Native Android runtime startup, physical-device AR calibration, stress/performance profiling, and lifecycle soak tests remain required before production certification. Soft-body simulation, fluids, AR depth/occlusion and scene reconstruction are separate capabilities and are not claimed as implemented.

## Camera ownership

The AR scene and hand-mirror experience are separate modes. ARCore/ARKit owns the camera while an AR session is active; opening a second Flutter camera stream at the same time would contend for the same hardware camera. The app therefore closes one experience before entering the other.

## Technology map

| Technology | Role | Current integration |
|---|---|---|
| Flutter | App UI, state and navigation | Integrated |
| ARCore / ARKit | World tracking, planes, anchors and hit tests | Integrated through flutter_reality; physical-device validation pending |
| Jolt Physics 5.6 | 3D rigid bodies, collision detection, CCD, sleeping, sensors, events, queries and joints | Native FFI adapter integrated; Android build/device verification pending |
| Physics-to-AR bridge | Sync active Jolt poses to anchor-local AR nodes | Implemented for placed sample props; device calibration pending |
| MediaPipe Hand Landmarker | 21 hand landmarks and pinch tracking | Integrated live-stream path; device validation pending |
| MediaPipe Object Detector | Object labels and bounding boxes | Integrated still-frame analysis |
| MediaPipe Image Segmenter | Per-pixel category mask | Integrated still-frame analysis |
| SplatKit Android / Vulkan | Gaussian Splat rendering of SPZ and LODSPLAT worlds | Integrated native Android PlatformView; arm64/Vulkan device validation pending |
| EdgeSAM / SAM 2 | Promptable object cut-outs | Research/source reference only; not yet integrated into Android runtime |
| Depth Anything / AR depth | Metric depth and occlusion | Not yet integrated; ARCore depth support varies by device |
| NeRF | Alternative scene reconstruction pipeline | Research reference only; not integrated |
| Soft bodies / fluids | Deformable and fluid simulation | Not yet integrated |
| Voice / vision-language model | Natural-language scene commands | Typed allow-listed command contract only; speech runtime not integrated |

Jolt is built from source by the `just_jolt` native build hook. The app explicitly enables that hook in its own `pubspec.yaml`; without it, the package intentionally ships no native physics library. The bundled Jolt and joltc licenses are included by the package. Verify the resulting Android APK contains the native Jolt asset for each shipped ABI before release.

SplatKit Android is pinned to the published Maven Central artifact `io.github.xget7:splatkit-android:0.1.0-beta.3`. It requires Android 10/API 29+, arm64-v8a and Vulkan 1.1. Import a prepared `.spz` or `.lodsplat` file from the scene viewer. PLY reconstruction/preprocessing is an offline workflow; convert PLY with the SplatKit `prepare-world.sh` tooling before importing. Splat clouds are visual geometry and are not automatically collision-ready meshes.

The repository also retains separate research implementations under `Telekinesis-CV/`, `web-ar-hand-tracking/`, `splatkit/`, `arfoundation-samples/` and `xr_sandbox/`. These are source references, not automatically linked runtime modules. Check each upstream license before redistributing assets or code.

## MediaPipe model packaging

Models are declared as build-time bundled models. Run:

    flutter pub get
    dart run mediapipe_core:bundle_models
    flutter analyze
    flutter test
    flutter run

No model is silently downloaded at first launch. The explicit bundling step retrieves the package's pinned model files and verifies their digests.

## Android platform bootstrap

The initial Flutter commit did not include generated Android platform files. Create and configure the Android host once with:

    bash tool/bootstrap_android.sh

This generates the Flutter Android host and configures compileSdk 36, minSdk 29, arm64-v8a and the native SplatKit Vulkan dependency. Build and test on a physical ARCore-certified Android phone with Google Play Services for AR installed. The Gaussian Splat viewer additionally requires Vulkan 1.1. Jolt's native build hook compiles the engine for the selected Android ABI; validate cold start, resume and native library packaging on a physical device. Emulators can run unit tests but cannot validate camera tracking, AR, real-device Jolt behavior or Vulkan rendering.

## Privacy

Camera frames are processed locally by default. The app does not upload camera frames to a server. The sample GLB model is fetched from the Khronos public sample-assets repository when placed; replace it with bundled/licensed assets for offline production use.
