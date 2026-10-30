import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:kazumi/bean/widget/ios_scene_environment.dart';

/// Geometry is local to the video pane, including during split/folded playback.
/// A corner camera restricts overlapping controls, never the video rectangle.
class VideoViewportGeometry {
  const VideoViewportGeometry({
    required this.size,
    required this.padding,
    this.occlusions = const [],
    this.localizedEdges = EdgeInsets.zero,
  });

  factory VideoViewportGeometry.fromScene({
    required Rect pane,
    required Size window,
    required EdgeInsets padding,
    required IosSceneData scene,
  }) {
    final safe = Rect.fromLTRB(
      padding.left,
      padding.top,
      window.width - padding.right,
      window.height - padding.bottom,
    );
    final localPadding = EdgeInsets.fromLTRB(
      math.max(0, safe.left - pane.left),
      math.max(0, safe.top - pane.top),
      math.max(0, pane.right - safe.right),
      math.max(0, pane.bottom - safe.bottom),
    );
    final regions = scene.matches(window) ? scene.occlusions : const <Rect>[];
    // Only replace a full-edge inset when a finite, localized obstruction
    // explains it. Retain the system baseline for old/stale scene metrics.
    bool local(Rect r) =>
        r.width < window.width * .45 && r.height < window.height * .45;
    return VideoViewportGeometry(
      size: pane.size,
      padding: localPadding,
      localizedEdges: EdgeInsets.fromLTRB(
        regions.any((r) => local(r) && r.left < safe.left) ? 1 : 0,
        regions.any((r) => local(r) && r.top < safe.top) ? 1 : 0,
        regions.any((r) => local(r) && r.right > safe.right) ? 1 : 0,
        regions.any((r) => local(r) && r.bottom > safe.bottom) ? 1 : 0,
      ),
      occlusions: [
        for (final r in regions)
          if (r.overlaps(pane)) r.shift(-pane.topLeft),
      ],
    );
  }

  final Size size;
  final EdgeInsets padding;
  final List<Rect> occlusions;
  final EdgeInsets localizedEdges;

  EdgeInsets get basePadding => EdgeInsets.fromLTRB(
    localizedEdges.left > 0 ? 0 : padding.left,
    localizedEdges.top > 0 ? 0 : padding.top,
    localizedEdges.right > 0 ? 0 : padding.right,
    localizedEdges.bottom > 0 ? 0 : padding.bottom,
  );

  /// Content below the camera/status cluster can use the entire pane width.
  EdgeInsets get contentPadding => occlusions.isEmpty ? basePadding : padding;

  /// Find a horizontal interval for one control band. Top and bottom bands
  /// are evaluated independently, so rotating moves only the affected group.
  Rect place(Rect preferred, {double gap = 8}) {
    final safe = basePadding;
    var intervals = <(double, double)>[
      (safe.left + gap, size.width - safe.right - gap),
    ];
    for (final region in occlusions) {
      final blocked = region.inflate(gap);
      if (blocked.bottom <= preferred.top || blocked.top >= preferred.bottom) {
        continue;
      }
      intervals = [
        for (final interval in intervals) ...[
          if (blocked.left > interval.$1)
            (interval.$1, math.min(interval.$2, blocked.left)),
          if (blocked.right < interval.$2)
            (math.max(interval.$1, blocked.right), interval.$2),
        ],
      ];
    }
    Rect? best;
    var bestScore = double.infinity;
    for (final (left, right) in intervals) {
      final width = math.min(preferred.width, right - left);
      if (width <= 0) continue;
      final x = preferred.left.clamp(left, right - width);
      final candidate = Rect.fromLTWH(
        x,
        preferred.top,
        width,
        preferred.height,
      );
      final score =
          (preferred.width - width) * 10 +
          (candidate.center.dx - preferred.center.dx).abs();
      if (score < bestScore) {
        best = candidate;
        bestScore = score;
      }
    }
    return best ?? Rect.fromLTWH(safe.left, preferred.top, 0, preferred.height);
  }
}

class VideoViewportScope extends InheritedWidget {
  const VideoViewportScope({
    super.key,
    required this.geometry,
    required super.child,
  });
  final VideoViewportGeometry geometry;

  static VideoViewportGeometry of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<VideoViewportScope>()
          ?.geometry ??
      VideoViewportGeometry(
        size: MediaQuery.sizeOf(context),
        padding: MediaQuery.paddingOf(context),
      );

  @override
  bool updateShouldNotify(VideoViewportScope oldWidget) =>
      geometry != oldWidget.geometry;
}
