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

## Reconstruction and simulation status

The source now implements a bounded RGB-D reconstruction path: it reloads persisted synchronized frames, aligns depth and masks, projects masked points, fuses them into voxels, creates a voxel-derived surface, exports GLB 2.0, and bakes a static Jolt triangle-mesh collider. A structured tetrahedral volume is also generated from the fused occupancy and returned as `SoftBodyMeshData`.

The scan screen passes that local-space tetrahedral mesh into the native `VrixSoftBodyFfiEngine`, creates an XPBD body, performs an initial step/state read, and advances the native solver while the scan screen remains active. This confirms source-level solver wiring; it does **not** yet render the deformed vertices, exchange contacts/impulses with Jolt, or establish stable simulation quality on a physical scan. The manifest deliberately records `solverIntegrated: false` because the scan artifact is not a proof of a validated coupled simulation.

The following remain incomplete:
1. Higher-quality TSDF/Poisson/BPA or equivalent surface reconstruction and robust scan cleanup.
2. Rendering the live XPBD state as a deformed surface and synchronizing its collider.
3. Dynamic Jolt↔XPBD contact/impulse coupling and stable two-way interaction.
4. Tetrahedral element quality optimization beyond non-zero volume and conforming face incidence.
5. Independent GLB viewer validation, scan-to-ground-truth accuracy, and real-device performance/thermal acceptance.
6. EdgeSAM Android ONNX inference only after licensing, model hash, and runtime compatibility are verified; MediaPipe remains the fallback.

## Device acceptance

The physical reference target is LG V60 ThinQ 5G (LM-F100). CI tests cannot prove ARCore depth availability, camera/AR lifecycle arbitration, depth registration, thermal behavior or reconstruction quality. Those require a connected physical device and recorded test evidence. The reconstruction/export path is implemented in source but has not been exercised against a real captured scan or opened in an independent GLB viewer in this workflow.

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


## Implemented reconstruction code (November 2026)

- `lib/services/object_scan_reconstruction_service.dart` reads persisted RGB-D/mask/pose data and generates world-space masked points across depth-capable views.
- `lib/services/voxel_mesh_reconstruction.dart` builds a bounded exposed-voxel mesh, exports GLB 2.0 POSITION/NORMAL/index buffers, and exposes a Jolt static triangle-mesh collider bake method.
- `test/voxel_mesh_reconstruction_test.dart` covers a dense voxel block, sparse/over-budget rejection and GLB header/length.
- The scan screen exposes reconstruction after the capture session is completed and retains the Jolt world while the scan screen is active.
- Remaining: higher-quality TSDF/Poisson/BPA reconstruction, watertightness/normal validation on real scans, collider simplification, live XPBD deformation rendering, dynamic Jolt↔XPBD contact coupling, and physical-device performance/thermal acceptance.


## Tetrahedral volume and indexed boundary (follow-up)

- `lib/services/voxel_tetrahedralizer.dart` now creates a conforming structured tetrahedral volume from the fused occupied voxels: six tetrahedra per voxel, shared lattice vertices, a shared-face incidence map, rejection of non-manifold faces, non-zero rest-volume checks, and centering into object-local metres for the XPBD contract.
- The boundary is extracted from singly incident tetrahedral faces, oriented outward using each element's opposite vertex, and exported as an indexed surface. The same indexed boundary is used by the static Jolt collider path.
- `test/voxel_tetrahedralizer_test.dart` checks one-voxel and adjacent-voxel topology, boundary counts, volume validation, and budget rejection.
- The scan manifest records tetrahedral element counts and min/max six-volume. `solverIntegrated` remains false in the manifest because a generated mesh/runtime session is not equivalent to a validated Jolt↔XPBD coupled simulation.

Quality boundary: this is a structured voxel tetrahedralization, **not** constrained-Delaunay or quality-optimized tetrahedral meshing. The surface is still voxel-derived and can be blocky; it is not a TSDF/Poisson reconstruction. The generated tetrahedra are validated for finite non-zero rest volume and face incidence, but no arbitrary-shape aspect-ratio optimization, scan-to-ground-truth accuracy score, or device-derived quality acceptance has been established. Real captured scans and the target LG V60 remain required for those claims.
