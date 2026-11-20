# Reconstruction pipeline — implementation and acceptance

This workstream and the Jolt↔XPBD runtime converge into one final Android release candidate. They remain separate layers: rigid/deformable interaction does not turn the current RGB-D voxel baseline into photogrammetry, NeRF, or independent SLAM.

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

The app has registered RGB-D capture, masked point fusion, voxel occupancy mesh export and tetrahedral XPBD input. The AR renderer now has a native Filament GeometryNode bridge for bounded dynamic vertex/index buffers; the scan screen streams XPBD surface positions into the live AR scene. A Jolt kinematic sensor proxy queries rigid-body overlaps, feeds contact constraints to XPBD, and maps XPBD reactions back to dynamic Jolt bodies. A visible dynamic probe is rendered in AR so the contact path can be observed. These are interaction/rendering capabilities layered over the existing RGB-D baseline—not photogrammetry, NeRF, or independent SLAM. The GLB exporter currently emits positions/normals/indices; UVs and textures are not yet present.

The new reconstruction contracts enforce frame timing, camera intrinsics/pose, depth confidence and output metadata. Unavailable algorithms must return an explicit unsupported state; placeholder outputs are forbidden.

## Live AR deformation and Jolt↔XPBD acceptance

- The Flutter manager validates finite positions, triangle indices, transforms and mobile upload budgets before sending a mesh frame to the native renderer.
- The Android plugin owns the Filament geometry/material resources and updates vertex buffers in place; topology is fixed for one mesh lifetime.
- The scan runtime advances Jolt and XPBD in a deterministic order, refreshes sensor-proxy overlaps, applies XPBD contact constraints, and applies per-contact reaction impulses to dynamic rigid bodies.
- A low-poly rigid probe is also uploaded as an AR mesh and follows its Jolt body transform. This makes the test contact path visible instead of reporting only solver counters.
- Automated evidence includes native solver regression, Dart bridge validation, Jolt sensor-overlap tests and a native coupled-runtime test. The renderer is rate-limited to approximately 15 uploads/second on mobile and enforces 25,000 vertices / 50,000 triangles per dynamic mesh.
- Remaining acceptance: verify actual deformation, probe response, frame time, GPU memory, camera lifecycle and thermal behavior on the physical LG Wing LM-F100. CI does not replace this device test.

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
