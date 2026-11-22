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
using ::Matrix3r;
using ::Real;
using ::Vector3r;

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

struct ContactConstraint {
  bool active = false;
  Vector3r point = Vector3r::Zero();
  Vector3r normal = Vector3r::UnitY();
  Vector3r lambda_tangent = Vector3r::Zero();
  Real friction = 0;
  Real compliance = 0;
  Real lambda_normal = 0;
};

constexpr size_t kMaxContactsPerVertex = 4;

struct Body {
  std::vector<Vector3r> positions;
  std::vector<Vector3r> previous;
  std::vector<Vector3r> velocities;
  std::vector<Real> inverse_masses;
  std::vector<Tetrahedron> tetrahedra;
  std::vector<PointTarget> targets;
  std::vector<std::vector<ContactConstraint>> contacts;
  std::vector<Vector3r> reaction_forces;
  std::vector<uint32_t> reaction_samples;
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
  // XPBD multipliers are accumulated within one fixed timestep only.
  for (auto& vertex_contacts : body.contacts) {
    for (ContactConstraint& contact : vertex_contacts) {
      if (!contact.active) continue;
      contact.lambda_normal = 0;
      contact.lambda_tangent.setZero();
    }
  }

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
      (void)correction_target;
    }

    // Solve every independent rigid-body contact slot for this vertex.
    for (size_t i = 0; i < body.contacts.size(); ++i) {
      const Real inverse_mass = body.inverse_masses[i];
      if (inverse_mass <= static_cast<Real>(0)) continue;
      for (ContactConstraint& contact : body.contacts[i]) {
        if (!contact.active) continue;
        const Real alpha = contact.compliance / (dt * dt);
        const Real constraint =
            (body.positions[i] - contact.point).dot(contact.normal);
        const Real delta_lambda =
            (-constraint - alpha * contact.lambda_normal) /
            (inverse_mass + alpha);
        const Real next_lambda =
            std::max(static_cast<Real>(0),
                     contact.lambda_normal + delta_lambda);
        const Real applied_lambda = next_lambda - contact.lambda_normal;
        contact.lambda_normal = next_lambda;
        body.positions[i] +=
            inverse_mass * applied_lambda * contact.normal;

        const Vector3r displacement = body.positions[i] - body.previous[i];
        const Vector3r tangent =
            displacement - contact.normal * displacement.dot(contact.normal);
        const Real tangent_length = tangent.norm();
        if (contact.friction > 0 && tangent_length > static_cast<Real>(1e-9)) {
          Vector3r candidate =
              contact.lambda_tangent - tangent / inverse_mass;
          const Real maximum = contact.friction * contact.lambda_normal;
          const Real candidate_length = candidate.norm();
          if (candidate_length > maximum && candidate_length > 0) {
            candidate *= maximum / candidate_length;
          }
          const Vector3r delta_tangent = candidate - contact.lambda_tangent;
          contact.lambda_tangent = candidate;
          body.positions[i] += inverse_mass * delta_tangent;
        }
      }
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
  for (size_t i = 0; i < body.contacts.size(); ++i) {
    for (size_t slot = 0; slot < body.contacts[i].size(); ++slot) {
      const ContactConstraint& contact = body.contacts[i][slot];
      if (!contact.active) continue;
      const size_t reaction_index = i * kMaxContactsPerVertex + slot;
      body.reaction_forces[reaction_index] +=
          -(contact.lambda_normal * contact.normal +
            contact.lambda_tangent) / (dt * dt);
      ++body.reaction_samples[reaction_index];
    }
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
    body->contacts.resize(static_cast<size_t>(vertex_count));
    body->reaction_forces.resize(static_cast<size_t>(vertex_count) * kMaxContactsPerVertex,
                                 Vector3r::Zero());
    body->reaction_samples.resize(static_cast<size_t>(vertex_count) * kMaxContactsPerVertex, 0);

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
      Real volume = signed_volume(
          body->positions[tetra.indices[0]], body->positions[tetra.indices[1]],
          body->positions[tetra.indices[2]], body->positions[tetra.indices[3]]);
      if (!finite(volume) || std::abs(volume) <= static_cast<Real>(1e-9)) {
        return nullptr;
      }
      // The upstream FEM formulation builds Dm from (x1-x4, x2-x4, x3-x4).
      // Normalize winding so its rest volume is positive and F(rest) == I.
      if (volume < 0) {
        std::swap(tetra.indices[0], tetra.indices[1]);
        volume = -volume;
      }
      const Vector3r& p0 = body->positions[tetra.indices[0]];
      const Vector3r& p1 = body->positions[tetra.indices[1]];
      const Vector3r& p2 = body->positions[tetra.indices[2]];
      const Vector3r& p3 = body->positions[tetra.indices[3]];
      Matrix3r rest_matrix;
      rest_matrix.col(0) = p0 - p3;
      rest_matrix.col(1) = p1 - p3;
      rest_matrix.col(2) = p2 - p3;
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

VRIX_EXPORT int vrix_soft_body_set_contact(
    void* handle, int vertex_index, int contact_slot, const float* point_xyz,
    const float* normal_xyz, float friction, float compliance) {
  auto* body = static_cast<Body*>(handle);
  if (body == nullptr || body->disposed || point_xyz == nullptr ||
      normal_xyz == nullptr || vertex_index < 0 ||
      vertex_index >= static_cast<int>(body->positions.size()) ||
      contact_slot < 0 || contact_slot >= static_cast<int>(kMaxContactsPerVertex) ||
      !std::isfinite(friction) || friction < 0 ||
      !std::isfinite(compliance) || compliance < 0) {
    return 0;
  }
  Vector3r point(static_cast<Real>(point_xyz[0]),
                 static_cast<Real>(point_xyz[1]),
                 static_cast<Real>(point_xyz[2]));
  Vector3r normal(static_cast<Real>(normal_xyz[0]),
                  static_cast<Real>(normal_xyz[1]),
                  static_cast<Real>(normal_xyz[2]));
  const Real normal_length = normal.norm();
  if (!point.allFinite() || !normal.allFinite() ||
      !finite(normal_length) || normal_length <= static_cast<Real>(1e-8)) {
    return 0;
  }
  auto& contacts = body->contacts[static_cast<size_t>(vertex_index)];
  if (contacts.size() <= static_cast<size_t>(contact_slot)) {
    contacts.resize(static_cast<size_t>(contact_slot) + 1);
  }
  ContactConstraint& contact = contacts[static_cast<size_t>(contact_slot)];
  contact.active = true;
  contact.point = point;
  contact.normal = normal / normal_length;
  contact.friction = static_cast<Real>(friction);
  contact.compliance = static_cast<Real>(compliance);
  contact.lambda_normal = 0;
  contact.lambda_tangent.setZero();
  return 1;
}

VRIX_EXPORT int vrix_soft_body_clear_contact(void* handle, int vertex_index,
                                                int contact_slot) {
  auto* body = static_cast<Body*>(handle);
  if (body == nullptr || body->disposed || vertex_index < 0 ||
      vertex_index >= static_cast<int>(body->contacts.size()) ||
      contact_slot < 0 || contact_slot >= static_cast<int>(kMaxContactsPerVertex)) {
    return 0;
  }
  auto& contacts = body->contacts[static_cast<size_t>(vertex_index)];
  if (contacts.size() > static_cast<size_t>(contact_slot)) {
    contacts[static_cast<size_t>(contact_slot)] = ContactConstraint{};
  }
  return 1;
}

VRIX_EXPORT int vrix_soft_body_read_reaction_forces(
    void* handle, float* forces_xyz, int capacity) {
  auto* body = static_cast<Body*>(handle);
  if (body == nullptr || body->disposed || forces_xyz == nullptr ||
      capacity < static_cast<int>(body->reaction_forces.size())) {
    return 0;
  }
  for (size_t i = 0; i < body->reaction_forces.size(); ++i) {
    for (int axis = 0; axis < 3; ++axis) {
      const uint32_t samples = body->reaction_samples[i];
      forces_xyz[i * 3 + static_cast<size_t>(axis)] = samples == 0
          ? 0.0f
          : static_cast<float>(body->reaction_forces[i][axis] /
                               static_cast<Real>(samples));
    }
    body->reaction_forces[i].setZero();
    body->reaction_samples[i] = 0;
  }
  return static_cast<int>(body->reaction_forces.size());
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
