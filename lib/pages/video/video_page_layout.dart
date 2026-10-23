import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/ios_scene_environment.dart';
import 'package:kazumi/utils/adaptive_layout.dart';

typedef VideoPlayerLayout = ({bool fillsWindow, bool hasSidePanel});

/// One player subtree survives compact, expanded and tabletop layouts.
class VideoPageLayout extends StatelessWidget {
  const VideoPageLayout({
    super.key,
    required this.fullscreen,
    required this.isPip,
    required this.playerBuilder,
    required this.tabs,
    this.sidePanel,
  });

  final bool fullscreen;
  final bool isPip;
  final Widget Function(BuildContext context, VideoPlayerLayout layout)
  playerBuilder;
  final Widget tabs;
  final Widget? sidePanel;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final size = box.biggest;
      final padding = MediaQuery.paddingOf(context);
      final scene = IosSceneEnvironment.of(context);
      final divisions = <Rect>[
        if (scene.matches(size)) ...scene.divisions,
        for (final feature in MediaQuery.displayFeaturesOf(context))
          if (feature.type == ui.DisplayFeatureType.hinge ||
              (feature.type == ui.DisplayFeatureType.fold &&
                  feature.state == ui.DisplayFeatureState.postureHalfOpened))
            feature.bounds,
      ];
      final horizontalFold = AdaptiveLayout.horizontalDivision(size, divisions);
      final verticalFold = AdaptiveLayout.verticalDivision(size, divisions);
      final fillsWindow = horizontalFold == null && verticalFold == null
          ? AdaptiveLayout.playerFillsWindow(
              size,
              fullscreen: fullscreen,
              isPip: isPip,
            )
          : fullscreen || isPip;
      final columns =
          !fillsWindow &&
          horizontalFold == null &&
          AdaptiveLayout.usePlayerColumns(size);
      final hasSidePanel = fillsWindow && !isPip && sidePanel != null;
      final safe = Rect.fromLTRB(
        padding.left,
        padding.top,
        size.width - padding.right,
        size.height - padding.bottom,
      );
      Rect playerRect;
      Rect tabsRect;
      if (fillsWindow) {
        playerRect = Offset.zero & size;
        tabsRect = safe;
      } else if (horizontalFold != null) {
        playerRect = Rect.fromLTRB(
          safe.left,
          safe.top,
          safe.right,
          horizontalFold.top,
        );
        tabsRect = Rect.fromLTRB(
          safe.left,
          horizontalFold.bottom,
          safe.right,
          safe.bottom,
        );
      } else if (columns) {
        final panel = AdaptiveLayout.playerPanelWidth(safe.width);
        playerRect = Rect.fromLTRB(
          safe.left,
          safe.top,
          safe.right - panel - 16,
          safe.bottom,
        );
        tabsRect = Rect.fromLTRB(
          safe.right - panel,
          safe.top,
          safe.right,
          safe.bottom,
        );
      } else {
        final playerHeight = math.min(safe.width * 9 / 16, safe.height * .6);
        playerRect = Rect.fromLTWH(
          safe.left,
          safe.top,
          safe.width,
          playerHeight,
        );
        tabsRect = Rect.fromLTRB(
          safe.left,
          playerRect.bottom,
          safe.right,
          safe.bottom,
        );
      }
      if (!fillsWindow && verticalFold != null) {
        playerRect = Rect.fromLTRB(
          safe.left,
          safe.top,
          verticalFold.left,
          safe.bottom,
        );
        tabsRect = Rect.fromLTRB(
          verticalFold.right,
          safe.top,
          safe.right,
          safe.bottom,
        );
      }
      // Positions change, not widget ancestry. Folding must not dispose playback
      // or reset the active episode, tabs, focus and player control state.
      return Stack(
        children: [
          Positioned.fromRect(
            rect: playerRect,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(columns ? 20 : 0),
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  size: playerRect.size,
                  padding: fillsWindow ? padding : EdgeInsets.zero,
                  viewPadding: fillsWindow
                      ? MediaQuery.viewPaddingOf(context)
                      : EdgeInsets.zero,
                ),
                child: Builder(
                  builder: (context) => playerBuilder(context, (
                    fillsWindow: fillsWindow,
                    hasSidePanel: hasSidePanel,
                  )),
                ),
              ),
            ),
          ),
          Positioned.fromRect(
            rect: tabsRect,
            child: Offstage(
              offstage: fillsWindow,
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                removeBottom: true,
                removeLeft: true,
                removeRight: true,
                child: tabs,
              ),
            ),
          ),
          if (hasSidePanel) sidePanel!,
        ],
      );
    },
  );
}
