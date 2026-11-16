# VirxMagical — Digital Reality Engine

VirxMagical is an Android-first Flutter application for interactive digital representations of physical objects. The digital layer can be moved and transformed while the real source object remains unchanged.

## Implemented application paths

- Arabic-first Flutter app shell and navigation.
- **AR scene:** native ARCore/ARKit session through `flutter_reality`, horizontal/vertical plane detection, tap hit-testing, anchor creation, GLB sample placement, drag/rotate and remove.
- **Hand mirror:** camera preview plus Google's MediaPipe Hand Landmarker in live-stream mode. A pinch grabs and moves a digital overlay; the physical source object is never modified.
- **Scene analysis:** on-device MediaPipe Object Detector and Image Segmenter on a captured frame.
- **Unit tests:** normalized pinch-distance logic.

## Camera ownership

The AR scene and hand-mirror experience are separate modes. ARCore/ARKit owns the camera while an AR session is active; opening a second Flutter camera stream at the same time would contend for the same hardware camera. The app therefore closes one experience before entering the other.

## Technology map

| Technology | Role | Current integration |
|---|---|---|
| Flutter | App UI, state and navigation | Integrated |
| ARCore / ARKit | World tracking, planes, anchors and hit tests | Integrated through flutter_reality; physical-device validation pending |
| MediaPipe Hand Landmarker | 21 hand landmarks and pinch tracking | Integrated live-stream path; device validation pending |
| MediaPipe Object Detector | Object labels and bounding boxes | Integrated still-frame analysis |
| MediaPipe Image Segmenter | Per-pixel category mask | Integrated still-frame analysis |
| SplatKit Android / Vulkan | Gaussian Splat rendering of SPZ and LODSPLAT worlds | Integrated native Android PlatformView; arm64/Vulkan device validation pending |
| EdgeSAM / SAM 2 | Promptable object cut-outs | Research/source reference only; not yet integrated into Android runtime |
| Depth Anything / AR depth | Metric depth and occlusion | Not yet integrated; ARCore depth support varies by device |
| NeRF | Alternative scene reconstruction pipeline | Research reference only; not integrated |
| Physics / fluids | Digital rigid bodies, soft bodies and fluids | Not yet integrated in Flutter runtime |
| Voice / vision-language model | Natural-language scene commands | Not yet integrated |

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

This generates the Flutter Android host and configures compileSdk 36, minSdk 29, arm64-v8a and the native SplatKit Vulkan dependency. Build and test on a physical ARCore-certified Android phone with Google Play Services for AR installed. The Gaussian Splat viewer additionally requires Vulkan 1.1. Emulators can run unit tests but cannot validate camera tracking, AR or Vulkan rendering.

## Privacy

Camera frames are processed locally by default. The app does not upload camera frames to a server. The sample GLB model is fetched from the Khronos public sample-assets repository when placed; replace it with bundled/licensed assets for offline production use.
