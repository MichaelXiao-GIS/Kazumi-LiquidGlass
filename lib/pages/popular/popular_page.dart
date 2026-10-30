import 'package:kazumi/pages/menu/navigation_scroll_to_top.dart';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/widget/bangumi_mirror_error_widget.dart';
import 'package:kazumi/bean/widget/kazumi_menu.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/popular/popular_controller.dart';
import 'package:kazumi/bean/card/bangumi_card.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:window_manager/window_manager.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/platform/desktop_window_config.dart';
import 'package:kazumi/bean/appbar/drag_to_move_bar.dart' as dtb;
import 'package:kazumi/utils/device.dart';
import 'package:kazumi/utils/adaptive_layout.dart';

class PopularPage extends StatefulWidget {
  const PopularPage({super.key, required this.controller});

  final PopularController controller;

  @override
  State<PopularPage> createState() => _PopularPageState();
}

class _PopularPageState extends State<PopularPage> {
  late final ScrollController scrollController;
  NavigationScrollToTopController? _navigationScroll;
  PopularController get popularController => widget.controller;

  @override
  void initState() {
    super.initState();
    scrollController = ScrollController(
      initialScrollOffset: popularController.scrollOffset,
    );
    scrollController.addListener(scrollListener);
    if (popularController.trendList.isEmpty) {
      popularController.queryBangumiByTrend();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = NavigationScrollToTop.of(context)?.controller;
    if (controller != _navigationScroll) {
      _navigationScroll?.removeListener(_scrollToTop);
      _navigationScroll = controller;
      _navigationScroll?.addListener(_scrollToTop);
    }
  }

  void _scrollToTop() {
    if (!scrollController.hasClients) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      scrollController.jumpTo(0);
    } else {
      scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _navigationScroll?.removeListener(_scrollToTop);
    scrollController.removeListener(scrollListener);
    scrollController.dispose();
    super.dispose();
  }

  void scrollListener() {
    popularController.scrollOffset = scrollController.offset;
    if (scrollController.position.pixels >=
            scrollController.position.maxScrollExtent - 200 &&
        !popularController.isLoadingMore) {
      KazumiLogger().i(
        'PopularPageController: Fetching next recommendation batch',
      );
      if (popularController.currentTag != '') {
        popularController.queryBangumiByTag();
      } else {
        popularController.queryBangumiByTrend();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        controller: scrollController,
        slivers: [
          buildSliverAppBar(),
          SliverToBoxAdapter(
            child: Observer(
              builder: (_) => AnimatedOpacity(
                opacity: popularController.isLoadingMore ? 1.0 : 0.0,
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 300),
                child: popularController.isLoadingMore
                    ? const LinearProgressIndicator(minHeight: 4)
                    : const SizedBox(height: 4),
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              StyleString.cardSpace + MediaQuery.paddingOf(context).left,
              0,
              StyleString.cardSpace + MediaQuery.paddingOf(context).right,
              MediaQuery.paddingOf(context).bottom,
            ),
            sliver: Observer(
              builder: (_) {
                if (popularController.isTimeOut) {
                  return SliverToBoxAdapter(
                    child: SizedBox(
                      height: 400,
                      child: BangumiMirrorErrorWidget(
                        onRetry: () {
                          if (popularController.currentTag.isEmpty) {
                            popularController.queryBangumiByTrend();
                          } else {
                            popularController.queryBangumiByTag();
                          }
                        },
                        onSettingsReturned: () {
                          if (mounted) {
                            setState(() {});
                          }
                        },
                      ),
                    ),
                  );
                }
                // Read the observable contents here. SliverLayoutBuilder runs
                // later, outside this Observer, and cannot subscribe for us.
                final items = List<BangumiItem>.of(
                  popularController.currentTag.isEmpty
                      ? popularController.trendList
                      : popularController.bangumiList,
                );
                return contentGrid(items);
              },
            ),
          ),
        ],
      ),
      floatingActionButton:
          NavigationScrollToTop.of(context)?.inNavigation == true
          ? null
          : FloatingActionButton(
              onPressed: _scrollToTop,
              tooltip: '返回顶部',
              child: const Icon(Icons.arrow_upward),
            ),
    );
  }

  Widget contentGrid(List<BangumiItem> bangumiList) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final width = (constraints.crossAxisExtent - 16).clamp(
          0.0,
          double.infinity,
        );
        final scaler = MediaQuery.textScalerOf(context);
        final columns = AdaptiveLayout.posterColumns(width, scaler);
        final posterWidth = (width - spacing * (columns - 1)) / columns;
        return SliverPadding(
          padding: const EdgeInsets.all(8),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              mainAxisSpacing: 16,
              crossAxisSpacing: spacing,
              crossAxisCount: columns,
              mainAxisExtent: posterWidth / .65 + scaler.scale(16) * 2.8 + 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => BangumiCardV(bangumiItem: bangumiList[index]),
              childCount: bangumiList.length,
            ),
          ),
        );
      },
    );
  }

  Widget buildSliverAppBar() {
    final theme = Theme.of(context);
    final headerHeight = math.max(
      120.0,
      MediaQuery.textScalerOf(context).scale(34) * 1.3 + 32,
    );
    return SliverAppBar(
      pinned: true,
      stretch: true,
      expandedHeight: headerHeight,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      titleSpacing: 0,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarBrightness: theme.brightness,
        statusBarIconBrightness: theme.brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
      ),
      backgroundColor: theme.colorScheme.surface,
      actions: buildActions(),
      title: null,
      flexibleSpace: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            child: dtb.DragToMoveArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxExtent = headerHeight;
                  final t =
                      (1 -
                      ((constraints.maxHeight - kToolbarHeight) /
                              (maxExtent - kToolbarHeight))
                          .clamp(0.0, 1.0));
                  // 字重收缩后为 w500，展开时为 w700
                  final fontWeight = t < 0.5
                      ? FontWeight.w700
                      : FontWeight.w500;
                  final fontSize = lerpDouble(
                    theme.platform == TargetPlatform.iOS ? 34 : 28,
                    20,
                    t,
                  )!;
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(
                        left: 16,
                        top: 8,
                        bottom: 8,
                        right: 60,
                      ),
                      child: SizedBox(
                        height: math.max(
                          44,
                          MediaQuery.textScalerOf(context).scale(fontSize) *
                              1.3,
                        ),
                        child: Observer(
                          builder: (_) {
                            final bool isTrend =
                                popularController.currentTag == '';
                            return KazumiMenuButton(
                              animated: true,
                              style: const MenuStyle(
                                maximumSize: WidgetStatePropertyAll(
                                  Size(240, 350),
                                ),
                              ),
                              menuChildren: [
                                for (final tag in ['', ...defaultAnimeTags])
                                  KazumiMenuItem(
                                    label: tag.isEmpty ? '热门番组' : tag,
                                    selected:
                                        tag == popularController.currentTag,
                                    onPressed: () => _selectTag(tag),
                                  ),
                              ],
                              builder: (context, toggle) => InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: toggle,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        isTrend
                                            ? '热门番组'
                                            : popularController.currentTag,
                                        style: theme.textTheme.headlineMedium!
                                            .copyWith(
                                              fontWeight: fontWeight,
                                              fontSize: fontSize,
                                            ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.keyboard_arrow_down,
                                      size: fontSize,
                                      color: theme.iconTheme.color,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> buildActions() {
    return <Widget>[
      IconButton(
        tooltip: '搜索',
        onPressed: () => context.pushNamed('/search/'),
        icon: const Icon(Icons.search),
      ),
      IconButton(
        tooltip: '历史记录',
        onPressed: () => context.pushNamed('/settings/history/'),
        icon: const Icon(Icons.history),
      ),
      if (isDesktop() && !DesktopWindowConfig.showWindowButton)
        IconButton(
          tooltip: '退出',
          onPressed: () => windowManager.close(),
          icon: const Icon(Icons.close),
        ),
    ];
  }

  Future<void> _selectTag(String selected) async {
    if (!mounted || selected == popularController.currentTag) return;
    scrollController.animateTo(
      0,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
    popularController.setCurrentTag(selected);
    if (selected.isEmpty) {
      popularController.clearBangumiList();
      if (popularController.trendList.isEmpty) {
        await popularController.queryBangumiByTrend();
      }
    } else {
      await popularController.queryBangumiByTag(type: 'init');
    }
  }
}
