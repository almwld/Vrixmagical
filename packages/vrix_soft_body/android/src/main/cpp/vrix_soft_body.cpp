#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <limits>
#include <memory>
#include <new>
#include <vector>

#include "PositionBasedDynamics/XPBD.h"

#if defined(__GNUC__)
#define VRIX_EXPORT __attribute__((visibility("default")))
#else
#define VRIX_EXPORT
#endif

namespace {
using PBD::Matrix3r;
using PBD::Real;
using PBD::Vector3r;

struct Tetrahedron {
  std::array<uint32_t, 4> indices{};
  Real rest_volume = 0;
  Real lambda = 0;
  Matrix3r inverse_rest_matrix = Matrix3r::Identity();
};

struct PointTarget {
  bool active = false;
  Vector3r position = Vector3r::Zero();
  Real compliance = 0;
  Real lambda = 0;
};

struct Body {
  std::vector<Vector3r> positions;
  std::vector<Vector3r> previous;
  std::vector<Vector3r> velocities;
  std::vector<Real> inverse_masses;
  std::vector<Tetrahedron> tetrahedra;
  std::vector<PointTarget> targets;
  Real youngs_modulus = 25000;
  Real poisson_ratio = 0.35;
  Real damping = 0.02;
  Real fixed_dt = static_cast<Real>(1.0 / 60.0);
  int iterations = 8;
  int max_substeps = 4;
  Real accumulator = 0;
  bool disposed = false;
};

bool finite(Real value) { return std::isfinite(static_cast<double>(value)); }

Vector3r read_vec3(const float* values, size_t index) {
  return Vector3r(static_cast<Real>(values[index * 3]),
                  static_cast<Real>(values[index * 3 + 1]),
                  static_cast<Real>(values[index * 3 + 2]));
}

Real signed_volume(const Vector3r& p0, const Vector3r& p1,
                  const Vector3r& p2, const Vector3r& p3) {
  return (p1 - p0).cross(p2 - p0).dot(p3 - p0) / static_cast<Real>(6);
}

void solve_substep(Body& body) {
  const Real dt = body.fixed_dt;
  const Vector3r gravity(static_cast<Real>(0), static_cast<Real>(-9.81),
                         static_cast<Real>(0));
  const Real velocity_retention =
      std::max(static_cast<Real>(0), static_cast<Real>(1) - body.damping);

  for (size_t i = 0; i < body.positions.size(); ++i) {
    body.previous[i] = body.positions[i];
    if (body.inverse_masses[i] == 0) {
      body.velocities[i].setZero();
      continue;
    }
    body.velocities[i] =
        (body.velocities[i] + gravity * dt) * velocity_retention;
    body.positions[i] += body.velocities[i] * dt;
  }

  for (Tetrahedron& tetra : body.tetrahedra) tetra.lambda = 0;

  for (int iteration = 0; iteration < body.iterations; ++iteration) {
    for (Tetrahedron& tetra : body.tetrahedra) {
      const auto a = tetra.indices[0];
      const auto b = tetra.indices[1];
      const auto c = tetra.indices[2];
      const auto d = tetra.indices[3];
      Vector3r correction_a, correction_b, correction_c, correction_d;
      PBD::XPBD::solve_FEMTetraConstraint(
          body.positions[a], body.inverse_masses[a],
          body.positions[b], body.inverse_masses[b],
          body.positions[c], body.inverse_masses[c],
          body.positions[d], body.inverse_masses[d],
          tetra.rest_volume, tetra.inverse_rest_matrix,
          body.youngs_modulus, body.poisson_ratio, true, dt, tetra.lambda,
          correction_a, correction_b, correction_c, correction_d);
      body.positions[a] += correction_a;
      body.positions[b] += correction_b;
      body.positions[c] += correction_c;
      body.positions[d] += correction_d;
    }

    for (size_t i = 0; i < body.targets.size(); ++i) {
      PointTarget& target = body.targets[i];
      if (!target.active) continue;
      Vector3r correction_vertex, correction_target;
      const Real stiffness =
          target.compliance <= static_cast<Real>(0)
              ? static_cast<Real>(0)
              : static_cast<Real>(1) / target.compliance;
      PBD::XPBD::solve_DistanceConstraint(
          body.positions[i], body.inverse_masses[i], target.position,
          static_cast<Real>(0), static_cast<Real>(0), stiffness, dt,
          target.lambda, correction_vertex, correction_target);
      body.positions[i] += correction_vertex;
    }
  }

  for (size_t i = 0; i < body.positions.size(); ++i) {
    if (body.inverse_masses[i] == 0) {
      body.velocities[i].setZero();
    } else {
      body.velocities[i] = (body.positions[i] - body.previous[i]) / dt;
    }
  }
  for (PointTarget& target : body.targets) {
    if (target.active) target.lambda = 0;
  }
}
}  // namespace

extern "C" {

VRIX_EXPORT const char* vrix_soft_body_backend_name() {
  return "PositionBasedDynamics XPBD/FEM";
}

VRIX_EXPORT const char* vrix_soft_body_upstream_revision() {
  return VRIX_PBD_UPSTREAM_REVISION;
}

VRIX_EXPORT void* vrix_soft_body_create(
    const float* packed_positions, int vertex_count,
    const uint32_t* tetrahedron_indices, int tetrahedron_count,
    float density_kg_m3, float youngs_modulus_pa, float poisson_ratio,
    float damping, float fixed_dt_seconds, int solver_iterations,
    int max_substeps) {
  if (packed_positions == nullptr || tetrahedron_indices == nullptr ||
      vertex_count < 4 || tetrahedron_count < 1 ||
      !std::isfinite(density_kg_m3) || density_kg_m3 <= 0 ||
      !std::isfinite(youngs_modulus_pa) || youngs_modulus_pa <= 0 ||
      !std::isfinite(poisson_ratio) || poisson_ratio < 0 ||
      poisson_ratio > 0.49f || !std::isfinite(damping) || damping < 0 ||
      !std::isfinite(fixed_dt_seconds) || fixed_dt_seconds <= 0 ||
      solver_iterations < 1 || solver_iterations > 64 ||
      max_substeps < 1 || max_substeps > 16) {
    return nullptr;
  }

  try {
    auto body = std::make_unique<Body>();
    body->positions.reserve(static_cast<size_t>(vertex_count));
    for (int i = 0; i < vertex_count; ++i) {
      Vector3r point = read_vec3(packed_positions, static_cast<size_t>(i));
      if (!point.allFinite()) return nullptr;
      body->positions.push_back(point);
    }
    body->previous = body->positions;
    body->velocities.resize(static_cast<size_t>(vertex_count), Vector3r::Zero());
    body->inverse_masses.resize(static_cast<size_t>(vertex_count), 0);
    body->targets.resize(static_cast<size_t>(vertex_count));

    body->youngs_modulus = static_cast<Real>(youngs_modulus_pa);
    body->poisson_ratio = static_cast<Real>(poisson_ratio);
    body->damping = static_cast<Real>(damping);
    body->fixed_dt = static_cast<Real>(fixed_dt_seconds);
    body->iterations = solver_iterations;
    body->max_substeps = max_substeps;

    std::vector<Real> vertex_masses(static_cast<size_t>(vertex_count), 0);
    body->tetrahedra.reserve(static_cast<size_t>(tetrahedron_count));
    for (int i = 0; i < tetrahedron_count; ++i) {
      Tetrahedron tetra;
      for (int corner = 0; corner < 4; ++corner) {
        const uint32_t index = tetrahedron_indices[i * 4 + corner];
        if (index >= static_cast<uint32_t>(vertex_count)) return nullptr;
        for (int prior = 0; prior < corner; ++prior) {
          if (tetra.indices[prior] == index) return nullptr;
        }
        tetra.indices[corner] = index;
      }
      const Vector3r& p0 = body->positions[tetra.indices[0]];
      const Vector3r& p1 = body->positions[tetra.indices[1]];
      const Vector3r& p2 = body->positions[tetra.indices[2]];
      const Vector3r& p3 = body->positions[tetra.indices[3]];
      const Real volume = signed_volume(p0, p1, p2, p3);
      if (!finite(volume) || std::abs(volume) <= static_cast<Real>(1e-9)) {
        return nullptr;
      }
      Matrix3r rest_matrix;
      rest_matrix.col(0) = p1 - p0;
      rest_matrix.col(1) = p2 - p0;
      rest_matrix.col(2) = p3 - p0;
      if (std::abs(rest_matrix.determinant()) <= static_cast<Real>(1e-9)) {
        return nullptr;
      }
      tetra.rest_volume = volume;
      tetra.inverse_rest_matrix = rest_matrix.inverse();
      if (!tetra.inverse_rest_matrix.allFinite()) return nullptr;
      const Real mass = static_cast<Real>(density_kg_m3) * std::abs(volume) /
                        static_cast<Real>(4);
      for (uint32_t index : tetra.indices) vertex_masses[index] += mass;
      body->tetrahedra.push_back(tetra);
    }

    for (int i = 0; i < vertex_count; ++i) {
      const Real mass = vertex_masses[static_cast<size_t>(i)];
      if (mass > static_cast<Real>(1e-12)) {
        body->inverse_masses[static_cast<size_t>(i)] =
            static_cast<Real>(1) / mass;
      }
    }
    return body.release();
  } catch (const std::bad_alloc&) {
    return nullptr;
  } catch (...) {
    return nullptr;
  }
}

VRIX_EXPORT int vrix_soft_body_step(void* handle, float delta_seconds) {
  auto* body = static_cast<Body*>(handle);
  if (body == nullptr || body->disposed || !std::isfinite(delta_seconds) ||
      delta_seconds < 0) {
    return -1;
  }
  const Real maximum_frame_delta =
      body->fixed_dt * static_cast<Real>(body->max_substeps);
  body->accumulator += std::min(static_cast<Real>(delta_seconds),
                                maximum_frame_delta);
  int steps = 0;
  while (body->accumulator + static_cast<Real>(1e-9) >= body->fixed_dt &&
         steps < body->max_substeps) {
    solve_substep(*body);
    body->accumulator -= body->fixed_dt;
    ++steps;
  }
  return steps;
}

VRIX_EXPORT int vrix_soft_body_set_point_target(
    void* handle, int vertex_index, const float* target_xyz,
    float compliance) {
  auto* body = static_cast<Body*>(handle);
  if (body == nullptr || body->disposed || target_xyz == nullptr ||
      vertex_index < 0 ||
      vertex_index >= static_cast<int>(body->positions.size()) ||
      !std::isfinite(compliance) || compliance < 0) {
    return 0;
  }
  Vector3r target(static_cast<Real>(target_xyz[0]),
                  static_cast<Real>(target_xyz[1]),
                  static_cast<Real>(target_xyz[2]));
  if (!target.allFinite()) return 0;
  PointTarget& point = body->targets[static_cast<size_t>(vertex_index)];
  point.active = true;
  point.position = target;
  point.compliance = static_cast<Real>(compliance);
  point.lambda = 0;
  return 1;
}

VRIX_EXPORT int vrix_soft_body_clear_point_target(void* handle,
                                                   int vertex_index) {
  auto* body = static_cast<Body*>(handle);
  if (body == nullptr || body->disposed || vertex_index < 0 ||
      vertex_index >= static_cast<int>(body->targets.size())) {
    return 0;
  }
  body->targets[static_cast<size_t>(vertex_index)] = PointTarget{};
  return 1;
}

VRIX_EXPORT int vrix_soft_body_read_state(void* handle, float* positions,
                                          float* velocities, int capacity) {
  auto* body = static_cast<Body*>(handle);
  if (body == nullptr || body->disposed || positions == nullptr ||
      velocities == nullptr ||
      capacity < static_cast<int>(body->positions.size())) {
    return 0;
  }
  for (size_t i = 0; i < body->positions.size(); ++i) {
    for (int axis = 0; axis < 3; ++axis) {
      positions[i * 3 + static_cast<size_t>(axis)] =
          static_cast<float>(body->positions[i][axis]);
      velocities[i * 3 + static_cast<size_t>(axis)] =
          static_cast<float>(body->velocities[i][axis]);
    }
  }
  return static_cast<int>(body->positions.size());
}

VRIX_EXPORT void vrix_soft_body_destroy(void* handle) {
  delete static_cast<Body*>(handle);
}

}  // extern "C"
