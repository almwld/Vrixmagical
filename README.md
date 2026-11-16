# VirxMagical

VirxMagical is an Android-first Flutter application for a hybrid Digital Reality Engine: digital objects anchored to the physical world, with hand interaction, spatial understanding, simulated physics, lighting and AI-assisted scene perception.

## Initial Flutter milestone

- Arabic-first Material 3 interface.
- Home dashboard and navigation.
- Spatial Studio entry screen.
- Digital object library.
- Settings screen.
- Camera permission service.
- Flutter CI workflow and starter widget test.

The live AR camera renderer, ARCore plane/depth tracking, MediaPipe hand tracking, object segmentation, physics interaction, Gaussian Splat playback, fluids and AI scene understanding are not yet integrated. The interface explicitly presents these as planned work.

## Planned architecture

- Flutter: app shell, navigation, settings and asset management.
- Native Android / ARCore (or an embedded Unity runtime): camera tracking, planes, depth and occlusion.
- MediaPipe: hand landmarks and gestures.
- SAM 2 / mobile segmentation: object masks and tracking, subject to device and license evaluation.
- Depth estimation: ARCore Depth where supported; monocular fallback is an estimate.
- Physics: Unity PhysX or a compatible native simulation layer.
- Gaussian Splatting / NeRF: optional visual reconstruction; separate mesh proxies are required for reliable collision.
- Voice and vision-language model: scene-aware commands, with explicit consent for remote inference.

## Run

    flutter pub get
    flutter analyze
    flutter test
    flutter run

Install Flutter stable and Android SDK first. AR features require a compatible physical Android device.

See docs/INTEGRATION_STATUS.md and docs/ROADMAP.md.
