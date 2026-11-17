# VRIX Soft-Body Engine — integration decision and execution plan

## Operating rule

VRIX will integrate proven upstream components rather than reimplement mature simulation algorithms. Keep upstream source, license notices, version/commit pins and upstream test suites. Add only VRIX-specific adapter/contract tests for the seams between components. A passing upstream test suite does not prove Android ABI, renderer, AR lifecycle or device performance compatibility; those are separate integration gates.

No component is considered integrated merely because its source exists in this repository. Each stage must record source provenance, exact revision, license, retained tests, Android build evidence and device evidence separately.

## Existing VRIX boundaries (inspected)

- `VrixObject` is already the canonical identity for captured, library, generated and imported objects.
- `PhysicsSceneService` is the existing Jolt 5.6 rigid-body world and already accepts static triangle meshes and dynamic convex hulls.
- Jolt remains responsible for rigid bodies, broadphase/narrowphase collisions, rigid/deformable contact adapters and scene queries. It is not the deformable continuum solver.
- ARCore capture and the existing MediaPipe hand pipeline remain the perception/input owners. The soft-body engine must not open another camera or create another AR session.
- SplatKit/Vulkan is a rendering path; GPU deformation must consume solver output and must not become a second simulation authority.

## Upstream source audit

### Primary XPBD candidate: InteractiveComputerGraphics/PositionBasedDynamics

- Repository: https://github.com/InteractiveComputerGraphics/PositionBasedDynamics
- License: MIT (repository LICENSE; retain copyright and permission notice).
- Evidence: maintained C++ library with a dedicated `PositionBasedDynamics/XPBD.h/.cpp`; its API includes XPBD distance constraints, tetrahedral volume preservation and FEM tetrahedral constraints with Young's modulus, Poisson ratio and inversion handling.
- Scope fit: the best first candidate for the XPBD/FEM solver core. It already implements the mathematical primitives VRIX needs; do not write a parallel solver.
- Build caveat: upstream root CMake builds additional projects and fetches Discregrid and GenericParameters, while the solver library itself is a separate CMake target and depends on Eigen3. Android integration should build the minimal library target with pinned Eigen and NDK toolchain, not the desktop demos or full root project.
- Test provenance: the upstream repository tree currently exposes no dedicated unit-test target/folder. Do not claim an upstream test suite is retained where none is present. Preserve its solver demos/examples as upstream behavioral references, and add VRIX regression tests around the imported API (tetra volume, FEM response, inversion handling, determinism and bounded stepping). These are adapter/integration checks, not a replacement solver.
- Gate before vendoring: pin a reviewed commit; verify Eigen version/ABI, Android arm64-v8a and armeabi-v7a compilation, exception/RTTI/visibility settings, and preserve the upstream license and relevant examples. Confirm no required transitive component was omitted from the minimal target.

### Secondary reference: SOFA

- Repository: https://github.com/sofa-framework/sofa
- Core is LGPL-2.1-or-later; applications/tutorials are GPL and plugins can have their own licenses.
- SOFA is a mature FEM/continuum simulation framework, but its full framework/plugin and runtime footprint is not the first Android embedding choice. Use it as a reference or candidate for a separately justified component only after per-plugin license and mobile-build review. Do not pull GPL applications into the VRIX app.

### Excluded as primary source for now

Small demos and academic prototypes that implement only edge stretch/volume constraints are not substitutes for the maintained PositionBasedDynamics library's FEM tetra constraint and full upstream coverage. They may be useful as comparative references, not as the production engine.

## Stage 2 implementation added

- Added `packages/vrix_soft_body`, an Android Flutter plugin that builds `libvrix_soft_body.so` for arm64-v8a and exposes the solver through Dart FFI.
- The native plugin fetches Eigen 3.4.0 and PositionBasedDynamics at exact commit `10a70bc146a97873dc3c8fef372f5217e010542e`; it compiles only upstream XPBD, FEM support and math implementation files, not the upstream desktop framework, demos or Python bindings.
- The adapter constructs tetrahedral rest matrices, computes lumped vertex masses from density and rest volumes, integrates fixed timesteps, invokes the upstream XPBD FEM tetra constraint with inversion handling, and applies hand/touch point targets through the upstream XPBD distance constraint.
- XPBD Lagrange multipliers persist across solver iterations within a substep and reset between substeps.
- The plugin includes the upstream PositionBasedDynamics MIT notice. Eigen is fetched at its MPL-2.0 release tag; its upstream license remains in the fetched dependency source.
- Added a native CTest regression executable covering finite-state stepping, tetrahedral volume drift and hard point-target convergence. CI runs this host-side test and checks that the shared library is packaged into debug/release APKs and the AAB.
- The app now declares the plugin as a local path dependency. No UI, ARCore camera ownership or Jolt implementation was replaced.

### Stage 2 limitations that remain explicit

- Current native body creation assigns lumped masses from tetrahedral density; per-vertex pinned masses and heterogeneous material regions are not yet exposed in the Dart contract.
- The current contact boundary does not yet exchange deformable contact impulses with Jolt. Jolt remains the rigid scene owner; deformable-vs-rigid coupling is a later integration stage.
- The solver's native host regression must pass and Android NDK packaging must pass before this stage is considered build-verified. Physical performance and thermal behaviour remain unverified until tested on LG V60/LG Wing.

## Frozen VRIX adapter contracts

Implemented in `lib/domain/soft_body_contract.dart`:

- Mesh positions are packed XYZ in object-local metres; tetrahedra are packed four-index cells; render surface is packed triangle indices.
- Mesh validation rejects non-finite coordinates, out-of-range/repeated indices and degenerate rest tetrahedra.
- Material uses SI units: density kg/m³, Young's modulus Pa, Poisson ratio [0, 0.49], non-negative damping.
- Solver configuration bounds fixed timestep, iterations and catch-up substeps.
- `VrixSoftBodyEngine` exposes create/step/point-target/readback/remove/dispose without leaking XPBD, Jolt, ARCore or renderer types into UI code.
- Native handles are opaque. Simulation state is returned as immutable finite XYZ positions and velocities.
- Jolt owns rigid collision shapes; the future adapter exchanges contact/constraint data through a narrow boundary. No direct ownership of Jolt's internal pointers by Dart.

## Six-stage delivery sequence

1. **API and data contracts** — freeze mesh/material/config/handle/state/interaction contracts; map them to VrixObject and renderer without changing existing public APIs.
2. **XPBD core** — vendor the reviewed upstream library and its relevant tests; enable tetrahedral FEM/volume constraints and inversion handling. No home-grown fallback solver.
3. **Tetrahedral asset pipeline** — select a production tetrahedralizer with compatible license and Android/offline support; preserve source mesh, tetra topology, surface mapping and rest data. Do not confuse surface triangle meshes with tetrahedral volume meshes.
4. **ARCore + MediaPipe bridge** — map hand pinch/touch targets and ARCore world-space colliders into solver coordinates; reuse existing camera/session ownership.
5. **GPU deformation** — upload solver positions through the existing rendering path, with CPU fallback and bounded buffers. GPU is a renderer, never a competing solver.
6. **Organic response** — add breathing/secondary motion as bounded procedural forces/targets after physical stability, not as a substitute for physical constraints.

## Acceptance gates

- **Source gate:** exact upstream commit, SPDX/license file, third-party notice and source test provenance are checked in.
- **Build gate:** Android native library compiles for the supported ABIs with pinned dependencies and no desktop-only dependencies.
- **Solver gate:** retained upstream tests pass; VRIX adapter tests cover unit conversion, topology mapping, handle lifetime and state-buffer sizing. Benchmark stability and volume drift over fixed deterministic scenes.
- **Integration gate:** Jolt contact mapping, AR coordinate transforms, pause/resume and disposal do not leak or double-step.
- **Device gate:** physical target LG V60 ThinQ (LM-F100) and LG Wing measurements include frame time, memory, thermals, solver iterations and mesh size. CI cannot claim this gate.
- **No overclaim:** until each gate is evidenced, mark that capability as planned/integration-pending rather than available.

## Current execution status

- Stage 1 contracts and the first native XPBD/FEM adapter are now implemented in the feature branch; CI evidence is pending.
- The upstream source is pinned and fetched reproducibly rather than copied into the app source tree; the exact MIT notice is retained.
- Tetrahedralizer selection, MediaPipe/ARCore interaction bridge, GPU deformation, Jolt deformable-contact coupling and organic response remain pending.
- Do not mark native integration as production-ready until native CTest, Flutter tests, Android NDK packaging and device benchmarks all pass.
