cmake_minimum_required(VERSION 3.22)
project(vrix_soft_body LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

include(FetchContent)
if(POLICY CMP0169)
  cmake_policy(SET CMP0169 OLD)
endif()
# Android cross-compilation must not build or execute Eigen documentation examples.
set(EIGEN_BUILD_DOC OFF CACHE BOOL "" FORCE)
set(EIGEN_BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)

# Eigen is the only math dependency used by the selected upstream solver files.
FetchContent_Declare(
  eigen
  GIT_REPOSITORY https://gitlab.com/libeigen/eigen.git
  GIT_TAG 3.4.0
  GIT_SHALLOW TRUE
)
FetchContent_MakeAvailable(eigen)

# Pin the exact reviewed upstream revision. We compile only the XPBD/FEM
# implementation and its two implementation dependencies; desktop demos,
# Python bindings and unrelated external projects are intentionally excluded.
FetchContent_Declare(
  position_based_dynamics
  GIT_REPOSITORY https://github.com/InteractiveComputerGraphics/PositionBasedDynamics.git
  GIT_TAG 10a70bc146a97873dc3c8fef372f5217e010542e
  GIT_SHALLOW FALSE
)
FetchContent_GetProperties(position_based_dynamics)
if(NOT position_based_dynamics_POPULATED)
  FetchContent_Populate(position_based_dynamics)
endif()

add_library(vrix_position_based_dynamics STATIC
  ${position_based_dynamics_SOURCE_DIR}/PositionBasedDynamics/XPBD.cpp
  ${position_based_dynamics_SOURCE_DIR}/PositionBasedDynamics/PositionBasedDynamics.cpp
  ${position_based_dynamics_SOURCE_DIR}/PositionBasedDynamics/MathFunctions.cpp
)
target_include_directories(vrix_position_based_dynamics PUBLIC
  ${position_based_dynamics_SOURCE_DIR}
  ${position_based_dynamics_SOURCE_DIR}/PositionBasedDynamics
)
target_link_libraries(vrix_position_based_dynamics PUBLIC Eigen3::Eigen)
target_compile_options(vrix_position_based_dynamics PRIVATE
  -Wno-unused-parameter -Wno-deprecated-declarations
)

add_library(vrix_soft_body SHARED vrix_soft_body.cpp)
target_link_libraries(vrix_soft_body PRIVATE vrix_position_based_dynamics)
target_compile_options(vrix_soft_body PRIVATE
  -Wall -Wextra -Werror -Wno-unused-parameter
  -fvisibility=hidden -fvisibility-inlines-hidden
)
target_link_options(vrix_soft_body PRIVATE "-Wl,-z,max-page-size=16384")

# Keep a copy of the exact upstream license in the Flutter package and include
# the upstream commit in build metadata for crash/telemetry provenance.
target_compile_definitions(vrix_soft_body PRIVATE
  VRIX_PBD_UPSTREAM_REVISION="10a70bc146a97873dc3c8fef372f5217e010542e"
)

option(VRIX_SOFT_BODY_BUILD_TESTS "Build the host-side XPBD integration regression test" OFF)
if(VRIX_SOFT_BODY_BUILD_TESTS)
  enable_testing()
  add_executable(vrix_soft_body_smoke_test tests/soft_body_solver_smoke.cpp)
  target_link_libraries(vrix_soft_body_smoke_test PRIVATE vrix_soft_body)
  add_test(NAME vrix_soft_body_smoke_test COMMAND vrix_soft_body_smoke_test)
endif()
