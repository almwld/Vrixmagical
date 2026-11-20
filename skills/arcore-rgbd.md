# Skill: ARCore anchors and RGB-D

## Trigger
Anchor placement, relocalization, depth capture, occlusion, scan registration or camera lifecycle.

## Inputs
ARCore frame, CPU RGB/depth images, pose matrix, image/depth intrinsics, tracking state and device capability.

## Steps
1. Keep one ARCore session/camera owner; never open a competing camera.
2. Convert column-major rigid transforms to normalized quaternion x,y,z,w.
3. Let AnchorNode follow the ARCore anchor pose; avoid applying placement twice.
4. Acquire RGB, pose and depth from the same Frame callback; close every Image promptly.
5. Use CPU image intrinsics for the CPU RGB-D pair and scale to depth dimensions.
6. Preserve frame and image timestamps, raw/automatic provenance, confidence and reprojection state.
7. Reject invalid depth, stale tracking, non-finite poses and unsupported registration transforms.

## Outputs
Native bridge, typed capture contract, tests and physical-device checklist.

## Validation
Test identity/quarter/half-turn quaternions, timestamp and intrinsics registration, confidence filtering, anchor lifecycle and relocalization. CI cannot establish real ARCore depth or occlusion.
