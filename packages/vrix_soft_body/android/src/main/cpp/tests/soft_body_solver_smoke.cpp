#include <cmath>
#include <cstdint>
#include <cstdio>
#include <vector>

extern "C" {
void* vrix_soft_body_create(const float*, int, const uint32_t*, int,
                            float, float, float, float, float, int, int);
int vrix_soft_body_step(void*, float);
int vrix_soft_body_set_point_target(void*, int, const float*, float);
int vrix_soft_body_read_state(void*, float*, float*, int);
void vrix_soft_body_destroy(void*);
}

namespace {
float volume(const float* p) {
  const float ax = p[3] - p[0], ay = p[4] - p[1], az = p[5] - p[2];
  const float bx = p[6] - p[0], by = p[7] - p[1], bz = p[8] - p[2];
  const float cx = p[9] - p[0], cy = p[10] - p[1], cz = p[11] - p[2];
  return (ax * (by * cz - bz * cy) +
          ay * (bz * cx - bx * cz) +
          az * (bx * cy - by * cx)) / 6.0f;
}
bool finite_state(const std::vector<float>& values) {
  for (float value : values) if (!std::isfinite(value)) return false;
  return true;
}
}  // namespace

int main() {
  const float rest_positions[] = {
      0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1,
  };
  const uint32_t tetrahedra[] = {0, 1, 2, 3};
  void* body = vrix_soft_body_create(
      rest_positions, 4, tetrahedra, 1,
      1000.0f, 25000.0f, 0.35f, 0.02f, 1.0f / 60.0f, 8, 4);
  if (body == nullptr) {
    std::fprintf(stderr, "XPBD failed to create a valid tetrahedral body.\n");
    return 1;
  }

  std::vector<float> positions(12), velocities(12);
  for (int frame = 0; frame < 120; ++frame) {
    if (vrix_soft_body_step(body, 1.0f / 60.0f) < 1 ||
        vrix_soft_body_read_state(body, positions.data(), velocities.data(), 4) != 4) {
      std::fprintf(stderr, "XPBD step/readback failed at frame %d.\n", frame);
      vrix_soft_body_destroy(body);
      return 2;
    }
  }

  if (!finite_state(positions) || !finite_state(velocities)) {
    std::fprintf(stderr, "XPBD produced a non-finite state.\n");
    vrix_soft_body_destroy(body);
    return 3;
  }
  const float deformed_volume = volume(positions.data());
  if (!std::isfinite(deformed_volume) || deformed_volume <= 0.0f ||
      std::abs(deformed_volume - (1.0f / 6.0f)) > 0.02f) {
    std::fprintf(stderr, "Tetrahedral volume drift exceeded tolerance: %f\n",
                 deformed_volume);
    vrix_soft_body_destroy(body);
    return 4;
  }

  const float anchor[] = {0, 0, 0};
  if (vrix_soft_body_set_point_target(body, 0, anchor, 0.0f) != 1) {
    std::fprintf(stderr, "XPBD rejected a hard point target.\n");
    vrix_soft_body_destroy(body);
    return 5;
  }
  for (int frame = 0; frame < 30; ++frame) {
    if (vrix_soft_body_step(body, 1.0f / 60.0f) < 1) {
      std::fprintf(stderr, "XPBD failed while resolving the point target.\n");
      vrix_soft_body_destroy(body);
      return 6;
    }
  }
  if (vrix_soft_body_read_state(body, positions.data(), velocities.data(), 4) != 4 ||
      std::sqrt(positions[0] * positions[0] +
                positions[1] * positions[1] +
                positions[2] * positions[2]) > 0.03f) {
    std::fprintf(stderr, "XPBD point target did not converge.\n");
    vrix_soft_body_destroy(body);
    return 7;
  }

  vrix_soft_body_destroy(body);
  std::puts("XPBD tetrahedral FEM smoke test passed.");
  return 0;
}
