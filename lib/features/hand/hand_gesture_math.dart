import 'dart:math' as math;
import 'package:flutter/widgets.dart';

class HandGestureMath {
  const HandGestureMath._();

  static double distance(Offset a, Offset b) =>
      math.sqrt(math.pow(a.dx - b.dx, 2) + math.pow(a.dy - b.dy, 2));

  static bool isPinching(Offset thumbTip, Offset indexTip, {double threshold = 0.055}) =>
      distance(thumbTip, indexTip) <= threshold;
}
