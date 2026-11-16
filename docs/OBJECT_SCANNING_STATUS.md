# VRIX object scanning — current integration boundary

## Implemented in the Flutter app

- The existing rear-camera capture and MediaPipe Interactive Segmenter remain the live capture and mask-selection path.
- A user can capture several views of the same physical object, select/refine its foreground mask on each still image, and save each RGB image plus transparent PNG mask.
- Each scan is stored under the app support directory at `vrix_scans/<scan-id>/`.
- `scan_manifest.json` is versioned and records view index, image/mask filenames, source dimensions, capture timestamp and normalized positive prompt.
- A scan session cannot be marked captured until at least three views are saved. The store caps a session at 80 views and uses temporary-manifest replacement.
- Tests cover persistence, the minimum-view gate, completion lock, invalid prompts and missing source images.

## Explicitly not yet implemented

This is a durable multi-view **capture dataset**, not a reconstructed 3D object. The manifest intentionally records `cameraPose: null` and `depthMap: null`.

The next integration must:
1. Feed calibrated camera intrinsics and per-frame world poses from the active ARCore session (without opening a competing camera stream).
2. Enable ARCore Depth only after querying `Session.isDepthModeSupported`, then capture depth images and confidence/validity information.
3. Register each RGB/mask/depth frame into a common coordinate system and reject low-tracking-quality frames.
4. Fuse masked depth into a point cloud, filter outliers, estimate normals and generate a mesh/collider; Gaussian Splat reconstruction remains a separate output path.
5. Add EdgeSAM Android ONNX inference only after the model licence is cleared for the intended distribution, model SHA-256 is verified, and Android runtime compatibility is tested. The current MediaPipe segmenter remains the supported on-device fallback.

## Device acceptance

The physical reference target is LG V60 ThinQ 5G (LM-F100). CI tests cannot prove ARCore depth availability, camera/AR lifecycle arbitration, depth registration, thermal behavior or reconstruction quality. Those require a connected physical device and recorded test evidence.

## Safety and data handling

Captured photos and masks remain in app-private storage. No scan uploads are performed by this feature. Do not log image bytes, file contents or user-generated object imagery.
