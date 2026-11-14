import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:kazumi/pages/menu/navigation_scroll_to_top.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/embedded_native_control_area.dart';
import 'package:kazumi/pages/menu/ios_system_tabs.dart';
import 'package:kazumi/bean/widget/ios_bottom_scrim.dart';
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
  bool _nativeScrollToTop = false;

  void _setScrollToTopPlacement(bool shown) {
    if (_nativeScrollToTop != shown) setState(() => _nativeScrollToTop = shown);
  }

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
      if (Theme.of(context).platform == TargetPlatform.iOS) {
        final visible =
            media.viewInsets.bottom == 0 &&
            (ModalRoute.isCurrentOf(context) ?? true) &&
            RouteVisibility.nativeControlsVisibleOf(context);
        return Stack(
          fit: StackFit.expand,
          children: [
            NavigationScrollToTop(
              controller: _scrollToTop,
              inNavigation: visible && _nativeScrollToTop,
              child: widget.child,
            ),
            if (visible && media.padding.bottom > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: math.min(size.height, media.padding.bottom + 16),
                child: const IosBottomScrim(),
              ),
            if (visible)
              IosSystemTabs(
                selectedIndex: widget.selectedIndex,
                onSelected: (index) {
                  if (index == 0 && widget.selectedIndex == 0) {
                    _scrollToTop.scrollToTop();
                  } else {
                    widget.onSelected(index);
                  }
                },
                onSearch: widget.onSearch,
                onScrollToTop: widget.selectedIndex == 0
                    ? _scrollToTop.scrollToTop
                    : null,
                onScrollToTopPlacement: _setScrollToTopPlacement,
              ),
          ],
        );
      }

      // Keep the Material outlet in one position through window resizes.
      final itemHeight = media.textScaler.scale(58).clamp(58.0, 80.0);
      final verticalExtent = itemHeight * 4 + 68;
      final vertical =
          AdaptiveLayout.useSideNavigation(size) &&
          size.height - media.padding.vertical >= verticalExtent + 24;
      const railWidth = 64.0;
      final railLeft = media.padding.left + 8;
      final layoutInsets = EdgeInsets.only(
        left: vertical ? railLeft + railWidth + 8 : media.padding.left,
        right: media.padding.right,
        bottom: vertical
            ? media.padding.bottom
            : (media.viewInsets.bottom > 0 ? 0 : 80 + media.padding.bottom),
      );
      final pane = Rect.fromLTWH(
        layoutInsets.left,
        0,
        math.max(0, size.width - layoutInsets.horizontal),
        math.max(0, size.height - layoutInsets.vertical),
      );
      final contentMedia = media.copyWith(
        size: pane.size,
        padding: EdgeInsets.only(top: media.padding.top),
        viewPadding: EdgeInsets.only(top: media.viewPadding.top),
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
                child: MediaQuery(data: contentMedia, child: widget.child),
              ),
            ),
            if (media.viewInsets.bottom == 0)
              Positioned(
                left: vertical ? railLeft : media.padding.left,
                right: vertical ? null : media.padding.right,
                top: vertical
                    ? media.padding.top +
                          math.max(
                            12,
                            (size.height -
                                    media.padding.vertical -
                                    verticalExtent) /
                                2,
                          )
                    : null,
                bottom: vertical ? null : media.padding.bottom,
                width: vertical ? railWidth : null,
                height: vertical ? verticalExtent : 80,
                child: _materialNavigation(context, vertical),
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
