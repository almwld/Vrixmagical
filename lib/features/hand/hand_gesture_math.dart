import 'dart:math' as math;
import 'package:flutter/widgets.dart';

enum PinchEvent { pressed, released, lost }

/// Scale-invariant hand geometry and a debounced pinch state machine.
///
/// Coordinates are normalized MediaPipe landmarks. [imageAspectRatio] converts
/// x/y into the same pixel-proportional space before measuring distances.
class HandGestureMath {
  const HandGestureMath._();

  static double distance(Offset a, Offset b) =>
      math.sqrt(math.pow(a.dx - b.dx, 2) + math.pow(a.dy - b.dy, 2));

  static bool isPinching(Offset thumbTip, Offset indexTip, {double threshold = 0.055}) =>
      distance(thumbTip, indexTip) <= threshold;

  static double? pinchRatio(
    List<Offset> landmarks, {
    required double imageAspectRatio,
  }) {
    if (landmarks.length < 18 ||
        !imageAspectRatio.isFinite ||
        imageAspectRatio <= 0) {
      return null;
    }
    Offset px(Offset point) => Offset(point.dx * imageAspectRatio, point.dy);
    final thumb = px(landmarks[4]);
    final index = px(landmarks[8]);
    final wrist = px(landmarks[0]);
    final middleMcp = px(landmarks[9]);
    final indexMcp = px(landmarks[5]);
    final pinkyMcp = px(landmarks[17]);
    final palm = (distance(wrist, middleMcp) + distance(indexMcp, pinkyMcp)) / 2;
    if (!palm.isFinite || palm < 1e-6) return null;
    final ratio = distance(thumb, index) / palm;
    return ratio.isFinite ? ratio : null;
  }
}

/// OPEN -> CLOSING -> PINCHED -> OPENING -> OPEN.
///
/// Requires an observed open hand before arming, uses separate close/release
/// thresholds, and requires sustained evidence to prevent frame-to-frame flicker.
class PinchGesture {
  PinchGesture({
    this.closeThreshold = .30,
    this.releaseThreshold = .45,
    this.closeDwell = .07,
    this.releaseDwell = .06,
  }) : assert(closeThreshold < releaseThreshold);

  final double closeThreshold;
  final double releaseThreshold;
  final double closeDwell;
  final double releaseDwell;

  bool _armed = false;
  bool _pinched = false;
  double? _candidateSince;
  bool _releasing = false;

  bool get isPinched => _pinched;

  PinchEvent? update(double? ratio, double nowSeconds) {
    if (ratio == null || !ratio.isFinite || !nowSeconds.isFinite) {
      final wasPinched = _pinched;
      reset();
      return wasPinched ? PinchEvent.lost : null;
    }

    if (!_pinched) {
      if (ratio >= releaseThreshold) {
        _armed = true;
        _candidateSince = null;
        return null;
      }
      if (ratio <= closeThreshold && _armed) {
        _candidateSince ??= nowSeconds;
        if (nowSeconds - _candidateSince! >= closeDwell) {
          _pinched = true;
          _armed = false;
          _candidateSince = null;
          return PinchEvent.pressed;
        }
      } else {
        _candidateSince = null;
      }
      return null;
    }

    if (!_releasing) {
      if (ratio >= releaseThreshold) {
        _releasing = true;
        _candidateSince = nowSeconds;
      }
      return null;
    }

    if (ratio < releaseThreshold) {
      _releasing = false;
      _candidateSince = null;
      return null;
    }
    if (nowSeconds - _candidateSince! >= releaseDwell) {
      _pinched = false;
      _releasing = false;
      _armed = true;
      _candidateSince = null;
      return PinchEvent.released;
    }
    return null;
  }

  void reset() {
    _armed = false;
    _pinched = false;
    _releasing = false;
    _candidateSince = null;
  }
}
