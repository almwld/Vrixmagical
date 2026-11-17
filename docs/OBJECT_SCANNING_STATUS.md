# VRIX object scanning — current integration boundary

## Implemented in the Flutter app

- The scanner uses the existing `flutter_reality` ARView as the **single camera/session owner**; the VRIX-maintained local fork preserves the PlatformView and extends its existing frame callback. No second camera/session is opened.
- Each capture now requests a one-shot payload from the existing ARCore `onFrame` callback: CPU RGB image, camera pose, image intrinsics, depth/ confidence when available, tracking state and timestamps. MediaPipe Interactive Segmenter runs on that RGB image. The scanner no longer combines PixelCopy with a separate camera-pose call.
- The user can refine a foreground mask with touch prompts and save each RGB image, PNG mask, mask dimensions, prompt coordinates and 4x4 camera transform.
- The trusted camera pose and RGB/depth are sourced from the same ARCore Frame callback. The manifest schema is now version 3 and records frame identity, RGB image timestamp, per-stream intrinsics, raw/automatic depth provenance, depth-image timestamp, reprojection state, and confidence availability.
- Each scan is stored under the app support directory at `vrix_scans/<scan-id>/`; temporary AR captures are staged under `vrix_scans/_captures/`.
- `scan_manifest.json` schema v2 records view index, image/mask filenames, image and mask dimensions, capture timestamp, normalized prompt, and an explicit camera-pose trust state.
- A scan session cannot be marked captured until at least three views are saved. The store caps a session at 80 views and uses temporary-manifest replacement.
- The scanner is launched from the Spatial Studio's real object scanning tool. The former still-camera capture path remains available as a fallback.

## ARCore depth status

The vendored package `packages/flutter_reality_vrix` configures `RAW_DEPTH_ONLY` when supported, otherwise `AUTOMATIC`, otherwise `DISABLED`. The bridge acquires `acquireCameraImage()`, `acquireRawDepthImage16Bits()` plus `acquireRawDepthConfidenceImage()` (or automatic depth fallback) from the same `Frame` object inside the existing `onFrame` callback. Plane buffers are copied before each Android Image is closed. Raw-depth reprojection is determined by comparing successive raw-depth image timestamps as documented by Google.

The legacy plugin `getCameraPose()` still exists for compatibility, but the scanner no longer calls it. The new MethodChannel request is fulfilled on a later rendered frame and does not call `session.update()` again.

## Explicitly not yet implemented

The scanner now persists synchronized RGB-D capture data when depth is available, together with segmentation masks and trusted per-frame poses. It still does **not** create a point cloud, mesh, GLB or collider automatically; reconstruction status remains `not_started` until those stages are integrated and validated.

The next integration must:
1. Compile and run the vendored VRIX fork on an Android build, then verify frame payload and depth capability on the physical LG V60; no second camera/session or extra `session.update()` is used.
2. Register RGB/mask/depth in one coordinate system, including image rotation/crop and depth-to-color UV mapping; reject non-tracking or low-confidence frames.
3. Fuse masked depth into a bounded point cloud, filter outliers, estimate normals and generate a mesh/collider. Gaussian Splat reconstruction remains a separate visual output path.
4. Add EdgeSAM Android ONNX inference only after model licensing is cleared, the model SHA-256 is verified, and Android runtime compatibility is tested. MediaPipe remains the on-device fallback.

## Device acceptance

The physical reference target is LG V60 ThinQ 5G (LM-F100). CI tests cannot prove ARCore depth availability, camera/AR lifecycle arbitration, depth registration, thermal behavior or reconstruction quality. Those require a connected physical device and recorded test evidence.

## Safety and data handling

Captured photos and masks remain in app-private storage. No scan uploads are performed by this feature. Do not log image bytes, file contents or user-generated object imagery.

## New calibrated data contracts (November 2026)

- `packages/flutter_reality_vrix` vendors the upstream `flutter_reality 0.1.0` public API and Android PlatformView implementation, adding a per-view MethodChannel fulfilled from the existing ARCore frame callback.
- `lib/domain/captured_frame.dart` defines the RGB-D frame boundary, depth capability state, stream-specific intrinsics and a shared ARCore frame identity.
- Frame validation rejects paused/stopped tracking, malformed intrinsics, non-finite data, non-affine poses, non-orthonormal rotations and depth payloads attached to a different ARCore frame callback.
- `DepthAligner` projects lower-resolution depth samples into RGB pixel coordinates using separate depth/RGB intrinsics and a nearest-surface z-buffer; it carries confidence through registration.
- `SegmentationMaskAligner` maps the lower-resolution segmenter output to the RGB grid using nearest-neighbor sampling.
- `MaskedPointCloudBuilder` filters by aligned segmentation mask, confidence, depth range and pixel stride, then back-projects points through the world-from-camera pose.
- `PointCloudVoxelFusion` performs bounded world-space voxel centroid reduction (default 1 cm); it is a point-cloud reducer, not a mesh reconstruction algorithm.
- Non-zero RGB image rotation is rejected until the native bridge provides an explicit image/depth registration transform.
- `ObjectScanStore` schema v3 persists RGB, masks, trusted pose, depth as little-endian float32 meters, confidence as uint8, intrinsics and frame/image timestamps.
- Unit tests cover timestamp synchronization, pose orthonormality, intrinsics, tracking state, depth registration, confidence rejection, point-cloud projection and persisted RGB-D artifacts.

ARCore raw-depth images can be reprojected from earlier depth measurements into the current frame; Google documents comparing successive raw-depth image timestamps to detect fresh measurements. Therefore the bridge carries both the current Frame timestamp and the depth Image timestamp, plus an explicit reprojected flag. The invariant is shared Frame identity, not naive equality between the RGB and raw-depth Image timestamps. See the ARCore Raw Depth guide: https://developers.google.com/ar/develop/java/depth/raw-depth.

The Android bridge and Flutter consumer are now wired in source. The CI workflow generates the Android host with `tool/bootstrap_android.sh` before dependency resolution and APK builds, so Kotlin/Gradle compilation is covered by the current PR workflow. This is not proof of physical-device depth support: LG V60 runtime evidence remains required.
