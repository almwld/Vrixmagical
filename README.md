# VirxMagical — Digital Reality Engine

VirxMagical is an Android-first Flutter application for interactive digital representations of physical objects. The digital layer can be moved and transformed while the real source object remains unchanged.

## Implemented application paths

- Arabic-first Flutter app shell and navigation.
- **AR scene:** native ARCore/ARKit session through `flutter_reality`, horizontal/vertical plane detection, tap hit-testing, anchors, GLB placement, drag/rotate and removal.
- **3D physics:** Jolt-backed rigid-body world through the isolated physics entrypoint of `stage_3d`; static AR surface colliders, dynamic digital props, fixed-step simulation, transform synchronization, interaction hand-off and explicit native resource disposal.
- **Hand mirror:** camera preview plus Google's MediaPipe Hand Landmarker in live-stream mode. A pinch grabs and moves a digital overlay; the physical source object is never modified.
- **Scene analysis:** on-device MediaPipe Object Detector and Image Segmenter on a captured frame.
- **Automated tests:** scene runtime, physics lifecycle/input validation and existing hand-interaction behavior.

## Physics architecture and current verification boundary

The physics service is deliberately separate from the AR renderer. Jolt owns rigid-body simulation; `flutter_reality`/ARCore owns camera tracking, anchors and visible GLB nodes. The bridge converts world-space physics poses into anchor-local render transforms and pauses transform writes while a user is dragging or rotating a node.

The current AR placement path creates a static box collider for the tapped surface and a dynamic box collider for the placed digital prop. The collider dimensions are explicit approximations for the sample Duck asset, not automatically generated mesh colliders. The Jolt integration is sourced through `stage_3d`'s physics-only entrypoint; the package currently labels its overall project as experimental beta. Do not interpret a successful Flutter compile as proof of hardware readiness.

**Not yet accepted as production complete:** Android native Jolt runtime validation, ARCore coordinate/scale calibration on physical devices, stress/performance profiling, collision-shape fitting for imported GLB assets, and lifecycle soak tests. Soft-body simulation, fluid simulation and AR depth/occlusion are separate capabilities and are not claimed as implemented.

## Camera ownership

The AR scene and hand-mirror experience are separate modes. ARCore/ARKit owns the camera while an AR session is active; opening a second Flutter camera stream at the same time would contend for the same hardware camera. The app therefore closes one experience before entering the other.

## Technology map

| Technology | Role | Current integration |
|---|---|---|
| Flutter | App UI, state and navigation | Integrated |
| ARCore / ARKit | World tracking, planes, anchors and hit tests | Integrated through flutter_reality; physical-device validation pending |
| Jolt Physics | 3D rigid bodies, collision detection and response | Wired through Stage 3D's physics API; Android runtime validation pending |
| Physics-to-AR bridge | Sync body transforms to anchor-local AR nodes | Implemented for placed sample props; device calibration pending |
| MediaPipe Hand Landmarker | 21 hand landmarks and pinch tracking | Integrated live-stream path; device validation pending |
| MediaPipe Object Detector | Object labels and bounding boxes | Integrated still-frame analysis |
| MediaPipe Image Segmenter | Per-pixel category mask | Integrated still-frame analysis |
| SplatKit Android / Vulkan | Gaussian Splat rendering of SPZ and LODSPLAT worlds | Integrated native Android PlatformView; arm64/Vulkan device validation pending |
| EdgeSAM / SAM 2 | Promptable object cut-outs | Research/source reference only; not yet integrated into Android runtime |
| Depth Anything / AR depth | Metric depth and occlusion | Not yet integrated; ARCore depth support varies by device |
| NeRF | Alternative scene reconstruction pipeline | Research reference only; not integrated |
| Soft bodies / fluids | Deformable and fluid simulation | Not yet integrated |
| Voice / vision-language model | Natural-language scene commands | Typed allow-listed command contract only; speech runtime not integrated |

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

This generates the Flutter Android host and configures compileSdk 36, minSdk 29, arm64-v8a and the native SplatKit Vulkan dependency. Build and test on a physical ARCore-certified Android phone with Google Play Services for AR installed. The Gaussian Splat viewer additionally requires Vulkan 1.1. Emulators can run unit tests but cannot validate camera tracking, AR, native Jolt or Vulkan rendering.

## Privacy

Camera frames are processed locally by default. The app does not upload camera frames to a server. The sample GLB model is fetched from the Khronos public sample-assets repository when placed; replace it with bundled/licensed assets for offline production use.
