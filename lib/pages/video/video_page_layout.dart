import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/widget/ios_scene_environment.dart';
import 'package:kazumi/bean/settings/settings_scroll_edge.dart';
import 'package:kazumi/utils/adaptive_layout.dart';
import 'package:kazumi/pages/video/video_viewport_geometry.dart';

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
      final ios = Theme.of(context).platform == TargetPlatform.iOS;
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
      final panelWidth = AdaptiveLayout.playerPanelWidth(safe.width);
      final railInset = math.min(padding.right, scene.rightRailInset);
      final edgePanel = Rect.fromLTWH(
        safe.right + railInset - panelWidth,
        0,
        panelWidth,
        size.height,
      );
      // A hidden native rail still contributes a safe inset to the selected
      // tab's controller. Release it only when UIKit reports this pane clear.
      final useRightEdge =
          ios &&
          columns &&
          verticalFold == null &&
          scene.matches(size) &&
          railInset > 0 &&
          !scene.occlusions.any(edgePanel.overlaps);
      Rect playerRect;
      Rect tabsRect;
      if (fillsWindow) {
        playerRect = Offset.zero & size;
        tabsRect = safe;
      } else if (horizontalFold != null) {
        playerRect = Rect.fromLTRB(0, 0, size.width, horizontalFold.top);
        tabsRect = Rect.fromLTRB(
          0,
          horizontalFold.bottom,
          size.width,
          size.height,
        );
      } else if (columns) {
        final boundary = useRightEdge
            ? edgePanel.left
            : safe.right - panelWidth;
        playerRect = Rect.fromLTRB(0, 0, boundary, size.height);
        tabsRect = Rect.fromLTRB(boundary, 0, size.width, size.height);
      } else {
        // Preserve a 16:9 inline frame and leave usable room for episode tabs.
        // Insets protect controls, rather than cutting a white strip out of
        // the black playback background.
        final availableHeight = math.max(0.0, safe.height - 160);
        final playerSize = applyBoxFit(
          BoxFit.contain,
          const Size(16, 9),
          Size(ios ? size.width : safe.width, availableHeight),
        ).destination;
        playerRect = Rect.fromLTWH(
          ios ? 0 : safe.left + (safe.width - playerSize.width) / 2,
          safe.top,
          ios ? size.width : playerSize.width,
          playerSize.height,
        );
        tabsRect = Rect.fromLTRB(0, playerRect.bottom, size.width, size.height);
      }
      if (!fillsWindow && verticalFold != null) {
        playerRect = Rect.fromLTRB(0, 0, verticalFold.left, size.height);
        tabsRect = Rect.fromLTRB(
          verticalFold.right,
          0,
          size.width,
          size.height,
        );
      }
      EdgeInsets insetsFor(Rect rect) => EdgeInsets.fromLTRB(
        math.max(0, safe.left - rect.left),
        math.max(0, safe.top - rect.top),
        math.max(0, rect.right - safe.right),
        math.max(0, rect.bottom - safe.bottom),
      );
      VideoViewportGeometry geometryFor(Rect rect) =>
          VideoViewportGeometry.fromScene(
            pane: rect,
            window: size,
            padding: padding,
            scene: scene,
          );
      // Positions change, not widget ancestry. Folding must not dispose playback
      // or reset the active episode, tabs, focus and player control state.
      final panelAtStatusArea =
          !fillsWindow && (columns || verticalFold != null);
      final tabsPadding = useRightEdge
          ? insetsFor(tabsRect).copyWith(right: padding.right - railInset)
          : ios
          ? geometryFor(tabsRect).contentPadding
          : insetsFor(tabsRect);
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value:
            panelAtStatusArea &&
                Theme.of(context).brightness == Brightness.light
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black),
            Positioned.fromRect(
              rect: playerRect,
              child: ClipRect(
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    size: playerRect.size,
                    padding: insetsFor(playerRect),
                    viewPadding: insetsFor(playerRect),
                  ),
                  child: VideoViewportScope(
                    geometry: geometryFor(playerRect),
                    child: Builder(
                      builder: (context) => playerBuilder(context, (
                        fillsWindow: fillsWindow,
                        hasSidePanel: hasSidePanel,
                      )),
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fromRect(
              rect: tabsRect,
              child: Offstage(
                offstage: fillsWindow,
                // Only one episode panel may own its GlobalKey at a time.
                child: hasSidePanel
                    ? const SizedBox.shrink()
                    : ColoredBox(
                        color: Theme.of(context).colorScheme.surface,
                        child: Padding(
                          // Episode and comment lists reserve their own final
                          // scroll inset, so the viewport reaches the home edge.
                          padding: ios
                              ? tabsPadding.copyWith(bottom: 0)
                              : tabsPadding,
                          child: MediaQuery(
                            data: MediaQuery.of(context).copyWith(
                              padding: EdgeInsets.only(
                                bottom: ios ? tabsPadding.bottom : 0,
                              ),
                              viewPadding: EdgeInsets.only(
                                bottom: ios ? tabsPadding.bottom : 0,
                              ),
                            ),
                            child: SettingsScrollEdge(child: tabs),
                          ),
                        ),
                      ),
              ),
            ),
            // A dismissed sidebar returns SizedBox.shrink(). It must never set
            // the Stack's size to zero and clip the playing video on fullscreen.
            if (hasSidePanel) Positioned.fill(child: sidePanel!),
          ],
        ),
      );
    },
  );
}
