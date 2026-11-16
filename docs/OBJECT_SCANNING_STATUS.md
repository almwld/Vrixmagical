# VRIX object scanning — current integration boundary

## Implemented in the Flutter app

- The scanner now uses the existing `flutter_reality` ARView as the **single camera/session owner**; it does not open a competing Flutter camera stream.
- Each capture obtains an AR scene snapshot from the active AR session and runs the existing on-device MediaPipe Interactive Segmenter on that captured image. The legacy camera-pose request is a separate native call and is retained only as an explicitly unverified candidate; it is never exposed as calibrated reconstruction input.
- The user can refine a foreground mask with touch prompts and save each RGB image, PNG mask, mask dimensions, prompt coordinates and 4x4 camera transform.
- Legacy camera-pose candidates are stored separately with `cameraPoseStatus: unverified-unsynchronized`; the trusted `cameraPose` field remains null until RGB, pose and depth arrive from one ARCore frame timestamp. The manifest schema is now version 2.
- Each scan is stored under the app support directory at `vrix_scans/<scan-id>/`; temporary AR captures are staged under `vrix_scans/_captures/`.
- `scan_manifest.json` schema v2 records view index, image/mask filenames, image and mask dimensions, capture timestamp, normalized prompt, and an explicit camera-pose trust state.
- A scan session cannot be marked captured until at least three views are saved. The store caps a session at 80 views and uses temporary-manifest replacement.
- The scanner is launched from the Spatial Studio's real object scanning tool. The former still-camera capture path remains available as a fallback.

## ARCore depth status

The pinned `flutter_reality 0.1.0` Android implementation checks `Session.isDepthModeSupported(Config.DepthMode.AUTOMATIC)` during session initialization and configures AUTOMATIC depth when supported, otherwise DISABLED. However, its public Dart API does not expose the depth image or confidence image, and its current Pigeon API has no depth-frame payload. Therefore this app does **not** yet persist depth maps or claim depth capture is complete.

The existing plugin's `getCameraPose()` implementation performs a one-shot `session.update()` before reading the camera pose. This is not called on a frame timer, but exact timestamp synchronization between that pose and the subsequent PixelCopy snapshot still needs a native plugin API that returns pose, intrinsics, tracking state and depth from the same rendered ARCore frame.

## Explicitly not yet implemented

This remains a multi-view RGB + mask capture dataset with unverified legacy pose candidates, not a calibrated reconstruction dataset or reconstructed 3D object. The manifest intentionally records `depthMap: null` and reconstruction status `not_started`.

The next integration must:
1. Maintain a VRIX fork of `flutter_reality` and extend its existing native `ArView.onFrame` callback to export camera pose, camera intrinsics, tracking state, timestamp and depth/confidence images from the **same ARCore frame**; avoid a second camera/session or a second `session.update()`.
2. Register RGB/mask/depth in one coordinate system, including image rotation/crop and depth-to-color UV mapping; reject non-tracking or low-confidence frames.
3. Fuse masked depth into a bounded point cloud, filter outliers, estimate normals and generate a mesh/collider. Gaussian Splat reconstruction remains a separate visual output path.
4. Add EdgeSAM Android ONNX inference only after model licensing is cleared, the model SHA-256 is verified, and Android runtime compatibility is tested. MediaPipe remains the on-device fallback.

## Device acceptance

The physical reference target is LG V60 ThinQ 5G (LM-F100). CI tests cannot prove ARCore depth availability, camera/AR lifecycle arbitration, depth registration, thermal behavior or reconstruction quality. Those require a connected physical device and recorded test evidence.

## Safety and data handling

Captured photos and masks remain in app-private storage. No scan uploads are performed by this feature. Do not log image bytes, file contents or user-generated object imagery.

## New calibrated data contracts (November 2026)

- `lib/domain/captured_frame.dart` defines the immutable-by-contract RGB-D frame boundary, depth capability state, stream-specific intrinsics and strict timestamp equality.
- Frame validation rejects paused/stopped tracking, malformed intrinsics, non-finite data, non-affine poses, non-orthonormal rotations and depth/RGB timestamp mismatches.
- `DepthAligner` projects lower-resolution depth samples into RGB pixel coordinates using separate depth/RGB intrinsics and a nearest-surface z-buffer; it carries confidence through registration.
- `SegmentationMaskAligner` maps the lower-resolution segmenter output to the RGB grid using nearest-neighbor sampling.
- `MaskedPointCloudBuilder` filters by aligned segmentation mask, confidence, depth range and pixel stride, then back-projects points through the world-from-camera pose.
- `PointCloudVoxelFusion` performs bounded world-space voxel centroid reduction (default 1 cm); it is a point-cloud reducer, not a mesh reconstruction algorithm.
- Non-zero RGB image rotation is rejected until the native bridge provides an explicit image/depth registration transform.
- Unit tests cover timestamp synchronization, pose orthonormality, intrinsics, tracking state, depth registration, confidence rejection and point-cloud projection.

These are implemented Dart contracts and deterministic processing primitives. They do **not** mean the Android bridge is already connected: the app still needs the maintained native plugin fork and the ARCore device probe before any depth-backed scan can be claimed.
