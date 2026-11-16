# Physics and Research Runtime Acceptance Status

Updated for `feature/production-jolt-physics`.

## Physics implementation

| Layer | Implemented | Verification boundary |
|---|---|---|
| Native 3D engine | Jolt Physics 5.6 via standalone `just_jolt` FFI build hook | Native Android packaging and physical-device startup still required |
| Rigid bodies | Static/dynamic/kinematic bodies, mass, damping, gravity factor, sleeping and continuous-collision mode | Device-level motion/CCD regression matrix pending |
| Collider shapes | Box, sphere, capsule, dynamic convex hull and static triangle mesh | Automatic GLB mesh extraction, compound collider authoring and per-asset collider import not yet wired |
| Contact response | Jolt broadphase/narrowphase, friction, restitution and sleeping | Scene-specific material tuning and contact regression tests pending |
| Continuous collision | Jolt linear-cast motion quality for fast dynamic bodies | High-speed tunneling test matrix pending |
| Sensors/events | Sensor bodies; buffered contact begin/end, sensor begin/end and activation events | App-specific gameplay consumers are not yet wired |
| Spatial queries | Batched Jolt raycast, overlap and box shape-cast hits with layer masks and ignore-body support | GLB mesh query authoring and query performance profiling pending |
| Constraints | Fixed, point, hinge, slider, distance and six-DOF joints; hinge/slider motors and limits | Constraint stress/limit regression tests pending |
| Fixed stepping | Bounded 60 Hz accumulator, capped substeps, native collision substeps | Frame-time profiling on target hardware pending |
| AR synchronization | Batch active-body pose reads -> anchor-local ARNode transforms; 30 Hz thresholded platform writes; drag/rotate hand-off | Physical coordinate/scale calibration and frame-time profiling pending |
| Resource lifecycle | Body/joint/world destruction, timer cancellation, app background/foreground pause | Repeated open/close soak test pending |

The runtime uses the standalone Jolt FFI package rather than a renderer-coupled 3D framework. Jolt is built from source with the package's native build hook, explicitly enabled in the consuming app. This avoids bundling an unrelated Filament renderer into the AR application.

## Known boundaries

- The sample Duck model uses a manually approximated box collider. Imported model collider metadata and automatic convex decomposition are not yet implemented.
- A tapped AR plane is represented by a finite static box. Plane extent estimation, tracked-plane updates and anchor-loss recovery still need device-level validation.
- The AR bridge converts body poses into anchor-local matrices. Tracking drift, anchor relocalization and interaction races need real-device tests.
- Transform hand-off uses Jolt's body interface to update position/rotation in place, preserving connected joints. Velocity is reset by default after a user drag.
- Soft bodies, fluids, AR depth occlusion and scene reconstruction remain separate unimplemented systems.

## Required production acceptance gates

1. CI: native hook build, dependency resolution, format, analyze, all tests and Android debug/release builds.
2. Android: verify Jolt native library packaging and startup on arm64-v8a, including cold start, app resume and repeated scene disposal.
3. AR: validate plane-local/world transform conversion, gravity direction, object scale, drag/rotation hand-off and anchor relocalization.
4. Physics: test stacked boxes, high-speed impacts/CCD, resting contacts, friction/restitution, sensors, event ordering, raycasts, joint limits/motors and many-body load.
5. Performance: record frame-time percentiles, native memory and thermal behavior with increasing body counts on LG V60 ThinQ 5G (LM-F100) and at least one newer ARCore-certified device.
6. Content: replace the sample model's hard-coded collider with explicit collider metadata or verified mesh/compound collider generation.
7. Only after all gates pass may the feature be labelled production-ready.

Original research directories remain unchanged for provenance and parity review.
