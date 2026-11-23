import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/ios_bottom_scrim.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/modules/comments/comment_item.dart';
import 'package:kazumi/pages/player/episode_comments_view.dart';
import 'package:kazumi/pages/video/episode_selection_panel.dart';
import 'package:kazumi/pages/video/video_page_layout.dart';

void main() {
  testWidgets(
    'portrait episode and comment viewports extend through the iOS bottom fade',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const bottom = 34.0;
      var ascending = true;
      final road = Road(
        name: '线路',
        data: List.generate(30, (i) => 'ep$i'),
        identifier: [],
      );
      final commentsList = List.generate(
        12,
        (i) => EpisodeCommentItem.fromJson({
          'user': {'nickname': '观众', 'avatar': <String, dynamic>{}},
          'content': '第 ${i + 1} 条评论',
          'replies': [],
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: const EdgeInsets.only(top: 44, bottom: bottom),
              viewPadding: const EdgeInsets.only(top: 44, bottom: bottom),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: VideoPageLayout(
              fullscreen: false,
              isPip: false,
              playerBuilder: (_, _) => const SizedBox.expand(),
              tabs: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(text: '选集'),
                        Tab(text: '评论'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          EpisodeSelectionPanel(
                            title: '剧集',
                            roads: [road],
                            selectedRoad: 0,
                            selectedEpisode: 1,
                            onEpisodeSelected: (_, _) {},
                            downloads: const {},
                          ),
                          StatefulBuilder(
                            builder: (context, setState) => EpisodeCommentsView(
                              episode: 1,
                              episodeInfo: null,
                              comments: ascending
                                  ? commentsList
                                  : commentsList.reversed.toList(),
                              isLoading: false,
                              hasError: false,
                              isAscending: ascending,
                              onToggleSort: () =>
                                  setState(() => ascending = !ascending),
                              onSelectEpisode: () {},
                              onRefresh: () {},
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final edge = find.byType(IosBottomScrim);
      expect(tester.getRect(edge), const Rect.fromLTWH(0, 794, 390, 50));
      expect(
        find.descendant(of: edge, matching: find.byType(BackdropFilter)),
        findsOneWidget,
      );
      final episodeList = find.descendant(
        of: find.byType(EpisodeSelectionPanel),
        matching: find.byType(CustomScrollView),
      );
      expect(tester.getRect(episodeList).bottom, 844);
      final position = tester
          .state<ScrollableState>(
            find.descendant(of: episodeList, matching: find.byType(Scrollable)),
          )
          .position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const ValueKey('grid-ep-0-30'))).bottom,
        lessThanOrEqualTo(844 - bottom),
      );
      expect(position.pixels, greaterThan(0));
      await tester.tap(find.text('评论'));
      await tester.pumpAndSettle();
      final comments = find.descendant(
        of: find.byType(EpisodeCommentsView),
        matching: find.byType(CustomScrollView),
      );
      expect(tester.getRect(comments).bottom, 844);
      expect(MediaQuery.paddingOf(tester.element(comments)).bottom, bottom);
      final commentPosition = tester
          .state<ScrollableState>(
            find.descendant(of: comments, matching: find.byType(Scrollable)),
          )
          .position;
      expect(commentPosition.pixels, 0);
      for (final label in ['最新', '最早']) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(commentPosition.pixels, 0);
        final first = ascending ? commentsList.first : commentsList.last;
        expect(find.byKey(ObjectKey(first)).hitTestable(), findsOneWidget);
      }
      commentPosition.jumpTo(commentPosition.maxScrollExtent);
      await tester.pumpAndSettle();
      commentPosition.jumpTo(commentPosition.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.text('共 12 条讨论 · 来自 Bangumi')).bottom,
        lessThanOrEqualTo(844 - bottom),
      );
      expect(edge, findsOneWidget);
      await tester.tap(find.text('选集'));
      await tester.pumpAndSettle();
      final restoredEpisodePosition = tester
          .state<ScrollableState>(
            find.descendant(of: episodeList, matching: find.byType(Scrollable)),
          )
          .position;
      // Returning to the episode tab reveals the currently playing episode.
      expect(restoredEpisodePosition.pixels, 0);
      expect(
        find.byKey(const ValueKey('grid-ep-0-1')).hitTestable(),
        findsOneWidget,
      );
    },
  );
  testWidgets('browsing other ranges and roads preserves the playing episode', (
    tester,
  ) async {
    final selections = <(int, int)>[];
    Road road(String name, int length) => Road(
      name: name,
      data: List.generate(length, (i) => 'ep$i'),
      identifier: [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EpisodeSelectionPanel(
            title: '剧集',
            roads: [road('主线路', 104), road('备用', 4)],
            selectedRoad: 0,
            selectedEpisode: 53,
            downloads: const {},
            onEpisodeSelected: (episode, road) =>
                selections.add((episode, road)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('grid-ep-0-53')), findsOneWidget);
    await tester.tap(find.text('101–104'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('grid-ep-0-104')));
    expect(selections, [(104, 0)]);
    await tester.tap(find.text('主线路'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('road-option-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('grid-ep-1-4')));
    expect(selections, [(104, 0), (4, 1)]);
    await tester.tap(find.byTooltip('定位当前集'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('grid-ep-0-53')).hitTestable(),
      findsOneWidget,
    );
    expect(selections, [(104, 0), (4, 1)]);
  });
}
