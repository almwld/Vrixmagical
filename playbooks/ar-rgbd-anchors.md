# Playbook: AR anchors and RGB-D

## Goal
Make anchor transforms, frame synchronization and depth registration deterministic.

## Steps
1. Preserve the single ARCore camera/session owner.
2. Validate matrix-to-quaternion conversion, x/y/z/w order and normalization.
3. Let AnchorNode own the world pose; verify anchor update/removal lifecycle.
4. Capture CPU RGB, pose, depth and confidence from one Frame callback.
5. Scale CPU image intrinsics to depth dimensions; preserve timestamps and reprojection metadata.
6. Test invalid depth, tracking pauses, crop/rotation, confidence and resource closure.
7. Run physical anchor/relocalization/occlusion tests on LM-F100.

## Acceptance
Kotlin/Dart tests and Android build pass; depth aligns to RGB; anchor round-trip and tracking behavior verified on device.
