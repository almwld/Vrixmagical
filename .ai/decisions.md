# Durable decisions

## 2026-11-20 — One orchestrator for repository AI delegation
Use one task orchestrator with specialized playbooks/skills and a shared toolbox. Specialists are invoked only for meaningful domain work; one writer per branch; reviewers are read-only; verification is independent. Durable memory stores decisions/evidence, never hidden reasoning or secrets.

## 2026-11-20 — Jolt and XPBD remain separate authorities
Jolt owns rigid-body collision/world stepping. XPBD owns deformable vertices/FEM. The bridge exchanges contact constraints and reaction impulses; neither engine steps recursively from callbacks.

## 2026-11-20 — Avoid double collision response
The deformable Jolt convex proxy must be a non-resolving sensor. Query overlap geometry each frame, feed the target-facing normal/point into XPBD, and apply XPBD reaction impulses to dynamic Jolt bodies. Do not let Jolt resolve the same proxy contact as well.

## 2026-11-20 — Native XPBD contact cardinality
The current native solver stores one contact constraint per vertex. Until native multi-manifold support exists, arbitrate one deterministic rigid-body owner per vertex and document the limitation.

## 2026-11-20 — Scan mesh coordinates
Tetrahedralized scan vertices are centered object-local metres. Preserve the world-space center separately and restore it with the scene transform when registering the Jolt proxy/render frame.

## 2026-11-20 — ARCore anchor transforms
ARCore Pose requires a normalized quaternion in x,y,z,w order. AnchorNode owns and tracks the anchor world pose; do not apply the same placement transform a second time.

## 2026-11-20 — RGB-D intrinsics
Depth and CPU RGB captured from the same ARCore frame share the camera image intrinsics. Scale those intrinsics to the depth dimensions; do not mix GPU texture crop intrinsics into the CPU RGB-D registration.

## 2026-11-20 — SplatKit/Vulkan ownership
Use the existing SplatKit C++/Vulkan renderer for Gaussian Splat display. Do not implement a parallel Vulkan renderer in Flutter. Splat data is visual geometry, not an automatic physics collider; use explicit prepared colliders.
