# Physics and Research Runtime Acceptance Status

Updated for `feature/production-jolt-physics`.

## Physics implementation

| Layer | Implemented | Verification boundary |
|---|---|---|
| Native 3D engine | Jolt Physics via Stage 3D's isolated Jolt API | CI compile and device runtime still required |
| Body types | Static surface and dynamic prop bodies | Kinematic/character APIs not yet exposed by the app adapter |
| Shapes | Box colliders with validated positive half-extents | Sphere/capsule/compound/mesh collider authoring not yet exposed by this app |
| Contact response | Delegated to Jolt (broadphase, narrowphase, friction, restitution, sleeping and CCD capabilities) | Contact events and per-scene tuning need app-level acceptance tests |
| Fixed stepping | Bounded 60 Hz accumulator with max-substep cap and backlog drop | Frame-time profiling on target hardware pending |
| AR synchronization | World pose -> anchor-local ARNode transform; manual drag/rotate -> physics teleport | Physical coordinate and scale calibration pending |
| Resource lifecycle | Explicit body destruction, world disposal, timer cancellation, app background/foreground pause | Repeated open/close soak test pending |

The adapter intentionally uses the physics-only Jolt entrypoint; it does not replace the current ARCore/ARKit renderer. The selected Stage 3D package currently describes its overall project as experimental beta, so this dependency is a native-engine integration candidate, not a completed production certification.

## Known boundaries

- The sample Duck model uses a manually approximated box collider. Imported model collider generation and per-asset collider metadata are not yet implemented.
- A tapped AR plane is represented by a finite static box. Plane extent estimation, tracked-plane updates and anchor-loss recovery still need device-level validation.
- The AR bridge converts body poses into anchor-local matrices. Tracking drift, anchor relocalization and interaction races need real-device tests.
- The current app adapter exposes static and dynamic boxes, not all Jolt shape, joint, vehicle, character, soft-body or fluid APIs.
- Soft bodies, fluids, AR depth occlusion and scene reconstruction remain separate unimplemented systems.

## Required production acceptance gates

1. CI: dependency resolution, format, analyze, all tests and Android debug/release builds.
2. Android: verify Jolt native library packaging and startup on arm64-v8a, including cold start, app resume and repeated scene disposal.
3. AR: validate plane-local/world transform conversion, gravity direction, object scale, drag/rotation hand-off and anchor relocalization.
4. Physics: test stacked boxes, high-speed impacts, resting contacts, friction/restitution, CCD tunneling, many-body load and world teardown.
5. Performance: record frame-time percentiles, native memory and thermal behavior with increasing body counts on LG V60 ThinQ 5G (LM-F100) and at least one newer ARCore-certified device.
6. Content: replace the sample model's hard-coded collider with explicit collider metadata or verified mesh/compound collider generation.
7. Only after all gates pass may the feature be labelled production-ready.

Original research directories remain unchanged for provenance and parity review.
