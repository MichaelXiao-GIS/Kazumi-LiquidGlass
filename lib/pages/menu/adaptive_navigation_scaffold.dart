import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:kazumi/pages/menu/navigation_scroll_to_top.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/embedded_native_control_area.dart';
import 'package:kazumi/bean/widget/ios_glass.dart';
import 'package:kazumi/bean/widget/ios_bottom_scrim.dart';
import 'package:kazumi/bean/widget/ios_scene_environment.dart';
import 'package:kazumi/pages/menu/route_visibility.dart';
import 'package:kazumi/utils/adaptive_layout.dart';

/// The outlet occupies one stable tree position through every fold/resize.
class AdaptiveNavigationScaffold extends StatefulWidget {
  const AdaptiveNavigationScaffold({
    super.key,
    required this.child,
    required this.selectedIndex,
    required this.onSelected,
    required this.onSearch,
  });
  final Widget child;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onSearch;

  @override
  State<AdaptiveNavigationScaffold> createState() =>
      _AdaptiveNavigationScaffoldState();
}

class _AdaptiveNavigationScaffoldState
    extends State<AdaptiveNavigationScaffold> {
  final _scrollToTop = NavigationScrollToTopController();

  @override
  void dispose() {
    _scrollToTop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final size = box.biggest;
      final media = MediaQuery.of(context);
      final ios = Theme.of(context).platform == TargetPlatform.iOS;
      final scene = IosSceneEnvironment.of(context);
      final sideRegions = scene.matches(size)
          ? scene.occlusions.where(
              (rect) =>
                  rect.center.dx > size.width * .8 &&
                  rect.width < size.width * .4 &&
                  rect.height < size.height * .6,
            )
          : const <Rect>[];
      final trailing = ios && sideRegions.isNotEmpty;
      final leadingRegions = scene.matches(size)
          ? scene.occlusions.where(
              (rect) =>
                  rect.center.dx < size.width * .2 &&
                  rect.width < size.width * .4 &&
                  rect.height < size.height * .6,
            )
          : const <Rect>[];
      final belowSystemRegion = ios && (trailing || leadingRegions.isNotEmpty);
      final itemHeight = media.textScaler.scale(58).clamp(58.0, 80.0);
      final barHeight = media.textScaler.scale(64).clamp(64.0, 88.0);
      final sideTop = belowSystemRegion
          ? (trailing ? sideRegions : leadingRegions).fold(
              media.padding.top,
              (value, rect) => math.max(value, rect.bottom),
            )
          : media.padding.top;
      final baseVerticalExtent = itemHeight * 4 + 68;
      final vertical =
          (AdaptiveLayout.useSideNavigation(size) || belowSystemRegion) &&
          size.height - sideTop - media.padding.bottom >=
              baseVerticalExtent + 24;
      final integratedScrollToTop =
          ios &&
          vertical &&
          widget.selectedIndex == 0 &&
          size.height - sideTop - media.padding.bottom >=
              baseVerticalExtent + 68 + 24;
      final verticalExtent =
          baseVerticalExtent + (integratedScrollToTop ? 68 : 0);
      const railWidth = 80.0;
      final bottomInset = media.viewInsets.bottom > 0
          ? 0.0
          : (ios
                ? barHeight + 20 + media.padding.bottom
                : 80 + media.padding.bottom);
      final contentInsets = EdgeInsets.only(
        left: vertical && !trailing
            ? (belowSystemRegion
                  ? math.max(railWidth, media.padding.left)
                  : railWidth + media.padding.left)
            : media.padding.left,
        right: vertical && trailing
            ? math.max(railWidth, media.padding.right)
            : media.padding.right,
        bottom: vertical ? media.padding.bottom : bottomInset,
      );
      // Lists scroll behind the bottom material; only their final items need
      // padding to clear the floating navigation and home gesture area.
      final scrollBottomInset = ios ? contentInsets.bottom : 0.0;
      final layoutInsets = ios ? EdgeInsets.zero : contentInsets;
      final pane = Rect.fromLTWH(
        layoutInsets.left,
        0,
        math.max(0, size.width - layoutInsets.horizontal),
        math.max(0, size.height - layoutInsets.vertical),
      );
      final contentMedia = media.copyWith(
        size: pane.size,
        padding: EdgeInsets.fromLTRB(
          ios ? contentInsets.left : 0,
          media.padding.top,
          ios ? contentInsets.right : 0,
          scrollBottomInset,
        ),
        viewPadding: EdgeInsets.fromLTRB(
          ios ? contentInsets.left : 0,
          media.viewPadding.top,
          ios ? contentInsets.right : 0,
          ios ? math.max(scrollBottomInset, media.viewPadding.bottom) : 0,
        ),
        displayFeatures: [
          for (final feature in media.displayFeatures)
            if (feature.bounds.right >= pane.left &&
                feature.bounds.left <= pane.right &&
                feature.bounds.bottom >= pane.top &&
                feature.bounds.top <= pane.bottom)
              ui.DisplayFeature(
                bounds: feature.bounds.intersect(pane).shift(-pane.topLeft),
                type: feature.type,
                state: feature.state,
              ),
        ],
      );
      return Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: layoutInsets,
                child: MediaQuery(
                  data: contentMedia,
                  child: NavigationScrollToTop(
                    controller: _scrollToTop,
                    inNavigation: integratedScrollToTop,
                    child: widget.child,
                  ),
                ),
              ),
            ),
            if (ios && scrollBottomInset > 0 && media.viewInsets.bottom == 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: math.min(size.height, scrollBottomInset + 16),
                child: const IosBottomScrim(),
              ),
            // Remove the platform view, rather than only clipping/offstaging it:
            // UIKit glass can otherwise draw its edges above a sliding route.
            if (media.viewInsets.bottom == 0 &&
                (!ios || RouteVisibility.nativeControlsVisibleOf(context)))
              Positioned(
                left: vertical
                    ? (trailing
                          ? null
                          : (belowSystemRegion ? 8 : media.padding.left + 8))
                    : media.padding.left + (ios ? 16 : 0),
                right: vertical
                    ? (trailing ? 8 : null)
                    : media.padding.right + (ios ? 16 : 0),
                top: vertical
                    ? sideTop +
                          (belowSystemRegion
                              ? 12
                              : math.max(
                                  12,
                                  (size.height -
                                          sideTop -
                                          media.padding.bottom -
                                          verticalExtent) /
                                      2,
                                ))
                    : null,
                bottom: vertical ? null : media.padding.bottom + (ios ? 10 : 0),
                width: vertical ? 64 : null,
                height: vertical ? verticalExtent : (ios ? barHeight : 80),
                child: ios
                    ? IosGlassNavigation(
                        vertical: vertical,
                        selectedIndex: widget.selectedIndex,
                        onSelected: widget.onSelected,
                        onSearch: widget.onSearch,
                        onScrollToTop: integratedScrollToTop
                            ? _scrollToTop.scrollToTop
                            : null,
                      )
                    : _materialNavigation(context, vertical),
              ),
          ],
        ),
      );
    },
  );

  Widget _materialNavigation(BuildContext context, bool vertical) {
    if (!vertical) {
      return NavigationBar(
        selectedIndex: widget.selectedIndex,
        onDestinationSelected: widget.onSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '推荐',
          ),
          NavigationDestination(
            icon: Icon(Icons.timeline_outlined),
            selectedIcon: Icon(Icons.timeline),
            label: '时间表',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_outline),
            selectedIcon: Icon(Icons.favorite),
            label: '追番',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '我的',
          ),
        ],
      );
    }
    return EmbeddedNativeControlArea(
      child: NavigationRail(
        minWidth: 64,
        selectedIndex: widget.selectedIndex,
        onDestinationSelected: widget.onSelected,
        leading: IconButton(
          tooltip: '搜索',
          onPressed: widget.onSearch,
          icon: const Icon(Icons.search),
        ),
        labelType: NavigationRailLabelType.selected,
        destinations: const [
          NavigationRailDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: Text('推荐'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.timeline_outlined),
            selectedIcon: Icon(Icons.timeline),
            label: Text('时间表'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.favorite_outline),
            selectedIcon: Icon(Icons.favorite),
            label: Text('追番'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: Text('我的'),
          ),
        ],
      ),
    );
  }
}
