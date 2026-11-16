# Roadmap

## M0 — Flutter and CI foundation
- [x] Arabic-first Flutter shell
- [x] Camera hand-mirror experience
- [x] AR session, plane detection and digital GLB placement
- [x] MediaPipe hand, object detection and segmentation tasks
- [x] Unit tests for pinch math
- [ ] Green CI and Android debug APK

## M1 — Validate real devices
- [ ] Test on at least one ARCore-certified Android phone
- [ ] Test hand tracking on front/back cameras and device rotations
- [ ] Record FPS, inference latency, memory and thermal behavior
- [ ] Add model cache and error recovery tests

## M2 — Digital-object manipulation
- [ ] Replace sample duck with an asset library and GLB import
- [ ] Add two-hand scale/rotation and stable pinch release
- [ ] Add digital-only collision proxies and physics
- [ ] Add persistent world anchors where supported

## M3 — Advanced perception
- [ ] Add ARCore Depth API and real-world occlusion
- [ ] Evaluate EdgeSAM mobile port / Interactive Segmenter prompt workflow
- [ ] Track object IDs across frames and preserve user-selected masks
- [ ] Add depth-aware placement and shadow estimation

## M4 — Reconstruction and simulation
- [ ] Select a mobile-compatible Gaussian Splat renderer
- [ ] Add splat playback with separate mesh collision proxies
- [ ] Add soft-body and fluid simulation only after performance benchmarks

## M5 — AI interaction
- [ ] Voice command pipeline
- [ ] Scene-aware assistant grounded in tracked object IDs
- [ ] Local-first inference and explicit consent for remote processing
