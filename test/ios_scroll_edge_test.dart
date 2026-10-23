import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/bean/card/bangumi_card.dart';
import 'package:kazumi/bean/widget/ios_bottom_scrim.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/menu/adaptive_navigation_scaffold.dart';
import 'package:kazumi/pages/popular/popular_controller.dart';
import 'package:kazumi/pages/popular/popular_page.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/theme.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _LocalPopularController extends PopularController {
  _LocalPopularController() {
    trendList.addAll([
      for (var id = 0; id < 48; id++)
        BangumiItem(
          id: id,
          type: 2,
          name: '番组$id',
          nameCn: '番组$id',
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
        ),
    ]);
  }

  @override
  Future<void> queryBangumiByTrend({String type = 'add'}) async {}
}

class _Stripes extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    for (var x = 0.0; x < size.width; x += 4) {
      canvas.drawRect(
        Rect.fromLTWH(x, 0, 4, size.height),
        Paint()..color = (x / 4).floor().isEven ? Colors.black : Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(_Stripes oldDelegate) => false;
}

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(900, 650),
  bool highContrast = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('window'),
      child: MaterialApp(
        theme: iosAppTheme(ThemeData()),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(bottom: 34),
            viewPadding: const EdgeInsets.only(bottom: 34),
            highContrast: highContrast,
          ),
          child: child!,
        ),
        home: AdaptiveNavigationScaffold(
          selectedIndex: 0,
          onSelected: (_) {},
          onSearch: () {},
          child: child,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform originalPaths;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('kazumi_scroll_edge_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = originalPaths;
    await directory.delete(recursive: true);
  });

  testWidgets(
    'side navigation leaves no clipped strip below a scrolling list',
    (tester) async {
      await _mount(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => ListView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom,
              ),
              children: const [
                SizedBox(
                  height: 2000,
                  child: ColoredBox(color: Color(0xffd54162)),
                ),
              ],
            ),
          ),
        ),
      );
      expect(tester.getRect(find.byType(ListView)).bottom, 650);
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('window')),
      );
      await tester.runAsync(() async {
        final snapshot = await boundary.toImage(pixelRatio: 1);
        final bytes = (await snapshot.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        for (var y = 614; y < 650; y++) {
          final index = (y * snapshot.width + 500) * 4;
          expect(
            bytes.getUint8(index) - bytes.getUint8(index + 1),
            greaterThan(20),
            reason: 'Content color must remain visible through the tint at $y',
          );
        }
        snapshot.dispose();
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('bottom material blurs content and allows touches through', (
    tester,
  ) async {
    var taps = 0;
    await _mount(
      tester,
      Scaffold(
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => taps++,
          child: CustomPaint(
            painter: _Stripes(),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(500, 630));
    expect(taps, 1);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('window')),
    );
    await tester.runAsync(() async {
      final snapshot = await boundary.toImage(pixelRatio: 1);
      final bytes = (await snapshot.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      int red(int x, int y) => bytes.getUint8((y * snapshot.width + x) * 4);
      expect((red(501, 100) - red(505, 100)).abs(), greaterThan(200));
      expect((red(501, 630) - red(505, 630)).abs(), lessThan(30));
      // A solid surface would be 242: the darker value retains the backdrop.
      expect(red(501, 630), inInclusiveRange(140, 220));
      snapshot.dispose();
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('high contrast uses an opaque bottom material', (tester) async {
    await _mount(tester, const Scaffold(), highContrast: true);
    expect(
      find.descendant(
        of: find.byType(IosBottomScrim),
        matching: find.byType(BackdropFilter),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(900, 650), const Size(390, 844)]) {
    testWidgets('popular final row clears the bottom controls at $size', (
      tester,
    ) async {
      await _mount(
        tester,
        PopularPage(controller: _LocalPopularController()),
        size: size,
      );
      final viewport = find.byType(CustomScrollView);
      expect(tester.getRect(viewport).bottom, size.height);
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: viewport, matching: find.byType(Scrollable)),
      );
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final lastCard = find.byWidgetPredicate(
        (widget) => widget is BangumiCardV && widget.bangumiItem.id == 47,
      );
      final bottomInset = size.width > 600 ? 34 : 118;
      expect(lastCard, findsOneWidget);
      expect(
        tester.getRect(lastCard).bottom,
        lessThanOrEqualTo(size.height - bottomInset),
      );
      expect(find.text('番组47'), findsOneWidget);
      expect(
        tester.getRect(find.byType(FloatingActionButton)).bottom,
        lessThanOrEqualTo(size.height - bottomInset),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
