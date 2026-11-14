import 'dart:math' as math;
import 'package:flutter/widgets.dart';

/// Measurements use the current pane, never the physical screen or device name.
abstract final class AdaptiveLayout {
  static bool useSideNavigation(Size size) =>
      size.height >= 400 &&
      (size.width >= 600 || (size.height < 500 && size.width >= 480));

  static bool usePlayerColumns(Size size) =>
      size.width >= 700 && size.height >= 500;

  static bool playerFillsWindow(
    Size size, {
    required bool fullscreen,
    required bool isPip,
  }) =>
      fullscreen ||
      isPip ||
      (!usePlayerColumns(size) && size.width > size.height);

  static int posterColumns(double width, TextScaler scaler) {
    final minimum = scaler.scale(140).clamp(140.0, 240.0);
    return ((width + 12) / (minimum + 12)).floor().clamp(1, 8);
  }

  /// The crease is a layout boundary only when the OS reports an active fold.
  static Rect? horizontalDivision(Size size, Iterable<Rect> divisions) {
    for (final rect in divisions) {
      if (rect.width >= size.width * .8 &&
          rect.height < 48 &&
          rect.top >= 160 &&
          size.height - rect.bottom >= 160) {
        return rect;
      }
    }
    return null;
  }

  static Rect? verticalDivision(Size size, Iterable<Rect> divisions) {
    for (final rect in divisions) {
      if (rect.height >= size.height * .8 &&
          rect.width < 48 &&
          rect.left >= 160 &&
          size.width - rect.right >= 160) {
        return rect;
      }
    }
    return null;
  }

  static double playerPanelWidth(double width) =>
      math.min(380, math.max(280, width * .34));
}
