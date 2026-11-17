# Third-party notices — VRIX Soft-Body

## PositionBasedDynamics

- Project: https://github.com/InteractiveComputerGraphics/PositionBasedDynamics
- Pinned revision: `10a70bc146a97873dc3c8fef372f5217e010542e`
- License: MIT
- The complete upstream MIT license text is retained at `android/src/main/resources/META-INF/LICENSE-PositionBasedDynamics.txt`.
- VRIX compiles the upstream XPBD/FEM implementation and its required math support; the VRIX adapter is maintained separately.

## Eigen

- Project: https://gitlab.com/libeigen/eigen
- Pinned release: `3.4.0`
- License: Mozilla Public License 2.0 (MPL-2.0).
- Eigen is fetched as a build dependency; its original source and license files remain in the CMake FetchContent build tree. No Eigen source files are modified or copied into the VRIX package.
