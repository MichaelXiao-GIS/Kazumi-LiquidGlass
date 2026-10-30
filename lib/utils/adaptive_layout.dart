import 'dart:math' as math;
import 'package:flutter/widgets.dart';

/// Measurements use the current pane, never the physical screen or device name.
abstract final class AdaptiveLayout {
  static bool useSideNavigation(Size size) =>
      size.height >= 400 &&
      (size.width >= 600 || (size.height < 500 && size.width >= 480));

  /// Align to the camera, not the union of camera and status avoidance bounds.
  static double systemNavigationAxis(
    Iterable<Rect> regions, {
    required bool trailing,
  }) {
    final bounds = regions.reduce((a, b) => a.expandToInclude(b));
    for (final rect in regions) {
      if (rect.width > 0 &&
          rect.width <= 64 &&
          (rect.width - rect.height).abs() < 1) {
        return rect.center.dx;
      }
    }
    // The side status region extends 12pt farther toward the screen edge
    // than its visible content. UIKit 27.1 reports zero region margins here.
    // On an inner display with no camera cutout, compensate for that apron.
    return bounds.center.dx + (trailing ? -6 : 6);
  }

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
