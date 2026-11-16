# Integration status

Status labels distinguish code integration from runtime verification.

| Capability | Code status | Verification status |
|---|---|---|
| Flutter app shell / Arabic navigation | Integrated | CI pending |
| ARCore / ARKit session | Integrated via flutter_reality | Requires compatible physical device |
| Plane detection / hit testing / anchors | Integrated | Requires physical-device test |
| GLB digital object placement | Integrated using public Khronos sample URL | Requires network + physical-device test |
| Hand landmarks | Integrated via MediaPipe live stream | Requires camera/model/device test |
| Pinch-to-grab digital overlay | Integrated | Requires physical-device test |
| Object detection | Integrated for captured frames | Requires model bundle + device test |
| Image segmentation | Integrated for captured frames | Requires model bundle + device test |
| SAM 2 / EdgeSAM interactive cut-out | Research reference only | Not integrated into Flutter runtime |
| AR depth / occlusion | Not integrated | Device capability and API selection required |
| Gaussian Splat rendering | Source reference only (`splatkit/`) | No Flutter renderer integration |
| Rigid-body physics in AR | Not integrated | Requires native/engine selection |
| Fluids / soft bodies | Not integrated | Research / performance evaluation required |
| Voice commands / VLM | Not integrated | Privacy and model selection required |
| Android APK build | CI bootstrap configured | Must pass GitHub Actions |

Do not mark a capability complete solely because a package is declared or a screen exists. Runtime AR, hand tracking and segmentation require tests on a physical device.
