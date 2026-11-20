# Reconstruction pipeline — implementation and acceptance

This workstream is independent of the Jolt↔XPBD coupling PR. It converges into one final Android release candidate, but implementation remains split into reviewable commits so a green build cannot conceal missing algorithms.

## Required pipelines

| Pipeline | Required implementation | Acceptance evidence |
|---|---|---|
| RGB-D | synchronized ARCore RGB/depth, confidence filtering, metric fusion, surface reconstruction | repeatable scan, scale error report, valid GLB and collider |
| Photogrammetry | feature extraction/matching, outlier rejection, SfM, bundle adjustment, MVS and dense reconstruction | known-scale image set, camera/point-cloud error metrics, textured mesh |
| NeRF | dataset preparation, camera calibration, training/inference backend, checkpoint and export lifecycle | reproducible scene, held-out view quality, runtime/memory report |
| SLAM | tracked trajectory, map/landmark representation, relocalization and loop-closure evaluation | trajectory benchmark (ATE/RPE), relocalization and drift report |
| Photos/video | timestamped frame extraction, blur/coverage selection, synchronized poses and reconstruction input | deterministic video ingest and multi-view coverage tests |
| Meshes/textures | topology validation, UV unwrap, texture baking/atlas, PBR material export, simplification | GLB validator + independent viewer round-trip |
| Gaussian output | SplatKit only as a renderer for prepared splat assets | import/render/lifecycle tests; never count it as a reconstruction backend |

## Current implementation boundary

The app already has registered RGB-D capture, masked point fusion, voxel occupancy mesh export and tetrahedral XPBD input. These are the existing RGB-D baseline, not photogrammetry, NeRF, or a standalone SLAM implementation. The GLB exporter currently emits positions/normals/indices; UVs and textures are not yet present.

The new reconstruction contracts enforce frame timing, camera intrinsics/pose, depth confidence and output metadata. Unavailable algorithms must return an explicit unsupported state; placeholder outputs are forbidden.

## Implementation sequence

1. Harden shared capture sequence, coordinate/scale and artifact contracts; validate current GLB structure and topology.
2. Add deterministic video frame extraction and coverage/blur selection, reusing the single ARCore camera owner for live capture.
3. Integrate a real photogrammetry backend after evaluating COLMAP/OpenMVS or a maintained equivalent, licensing, Android ABI, offline/desktop execution and memory requirements.
4. Add SLAM trajectory/map export and benchmark against recorded ground truth; ARCore tracking alone is not acceptance.
5. Add a separately versioned NeRF training/inference adapter and reproducible dataset/checkpoint format. Select device or desktop execution based on measured constraints.
6. Add UV unwrap, texture baking/atlas, PBR GLB export and independent glTF validation.
7. Run the combined native XPBD + Flutter analyze/test + debug APK + release APK + split APK + AAB workflow once all pipelines are integrated.

## Release gate

A single final build means one release candidate after all required code and tests are merged—not one giant unreviewed code drop. CI success proves compilation and automated tests only. Physical-device ARCore, GPU, memory, thermal, camera lifecycle and reconstruction-quality tests must be reported separately. No pipeline is labelled complete until its acceptance evidence is attached.
