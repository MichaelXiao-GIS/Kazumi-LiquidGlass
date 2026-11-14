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
                          EpisodeCommentsView(
                            episode: 1,
                            episodeInfo: null,
                            comments: commentsList,
                            isLoading: false,
                            hasError: false,
                            isAscending: true,
                            onToggleSort: () {},
                            onSelectEpisode: () {},
                            onRefresh: () {},
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
        tester.getRect(find.byKey(const ValueKey('0:30'))).bottom,
        lessThanOrEqualTo(844 - bottom),
      );
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
      commentPosition.jumpTo(commentPosition.maxScrollExtent);
      await tester.pumpAndSettle();
      commentPosition.jumpTo(commentPosition.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.text('已显示全部 12 条讨论 · 来自 Bangumi')).bottom,
        lessThanOrEqualTo(844 - bottom),
      );
      expect(edge, findsOneWidget);
    },
  );
}
