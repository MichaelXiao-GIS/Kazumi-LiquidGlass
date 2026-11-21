import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_layout.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/pages/collect/collect_library_view.dart';
import 'package:kazumi/pages/info/rating_review_dialog.dart';

BangumiItem _item(int id) => BangumiItem(
  id: id,
  type: 2,
  name: '番剧$id',
  nameCn: '',
  summary: '',
  airDate: '',
  airWeekday: 1,
  rank: 0,
  images: {},
  tags: [],
  alias: [],
  ratingScore: 0,
  votes: 0,
  votesCount: [],
  info: '',
);

void _viewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  for (final compact in [true, false]) {
    testWidgets('review editor uses the correct route for compact=$compact', (
      tester,
    ) async {
      _viewport(tester, compact ? const Size(390, 844) : const Size(1024, 800));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showRatingReviewDialog(
                  context,
                  bangumiItem: _item(1),
                  onSubmit: (_) async => true,
                ),
                child: const Text('评分'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('评分'));
      await tester.pumpAndSettle();
      final editor = tester.element(find.byType(RatingReviewDialog));
      expect(
        ModalRoute.of(editor),
        compact
            ? isA<ModalBottomSheetRoute<bool>>()
            : isA<DialogRoute<bool>>(),
      );
      if (compact) {
        await tester.enterText(
          find.byKey(const ValueKey('review-comment')),
          '保留草稿',
        );
        await tester.tap(find.byTooltip('关闭'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('继续编辑'));
        await tester.pumpAndSettle();
        expect(find.text('保留草稿'), findsOneWidget);
      }
    });
  }

  testWidgets(
    'portrait library scrolls its search controls out and back into reach',
    (tester) async {
      _viewport(tester, const Size(390, 844));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: CollectLibraryView(
              entries: List.generate(
                30,
                (i) => CollectedBangumi(
                  _item(i),
                  DateTime.utc(2026),
                  CollectType.watching.value,
                ),
              ),
              showRating: false,
              onOpen: (_) {},
              onChangeType: (_, _) {},
              canEdit: (_) => false,
              layout: CollectLayout.list,
              onLayoutChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final search = find.byTooltip('搜索收藏').hitTestable();
      expect(search, findsOneWidget);
      await tester.dragFrom(const Offset(180, 600), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(search, findsNothing);
      await tester.dragFrom(const Offset(180, 180), const Offset(0, 660));
      await tester.pumpAndSettle();
      expect(search, findsOneWidget);
      await tester.tap(search);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
    },
  );
}
