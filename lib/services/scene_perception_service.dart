import 'package:mediapipe_vision/mediapipe_vision.dart';

class ScenePerceptionResult {
  const ScenePerceptionResult({
    required this.labels,
    required this.objectCount,
    required this.maskWidth,
    required this.maskHeight,
  });

  final List<String> labels;
  final int objectCount;
  final int maskWidth;
  final int maskHeight;
}

class ScenePerceptionService {
  const ScenePerceptionService._();

  static Future<ScenePerceptionResult> analyze(String imagePath) async {
    final image = VisionImage.fromFile(imagePath);
    final detector = await ObjectDetector.create(
      ObjectDetectorOptions(model: VisionModels.objectDetector, maxResults: 12, scoreThreshold: 0.35),
    );
    final segmenter = await ImageSegmenter.create(
      ImageSegmenterOptions(
        model: VisionModels.imageSegmenter,
        outputCategoryMask: true,
        outputConfidenceMasks: false,
      ),
    );
    try {
      final detections = await detector.detect(image);
      final segmentation = await segmenter.segment(image);
      final labelSet = <String>{};
      for (final detection in detections.detections) {
        if (detection.categories.isNotEmpty) {
          final name = detection.categories.first.categoryName;
          if (name != null && name.isNotEmpty) labelSet.add(name);
        }
      }
      final labels = labelSet.toList()..sort();
      final mask = segmentation.categoryMask;
      return ScenePerceptionResult(
        labels: labels,
        objectCount: detections.detections.length,
        maskWidth: mask?.width ?? 0,
        maskHeight: mask?.height ?? 0,
      );
    } finally {
      await detector.dispose();
      await segmenter.dispose();
    }
  }
}
