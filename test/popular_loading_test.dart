import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:mobx/mobx.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:kazumi/bean/card/bangumi_card.dart';
import 'package:kazumi/bean/widget/ios_scene_environment.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/popular/popular_controller.dart';
import 'package:kazumi/pages/popular/popular_page.dart';
import 'package:kazumi/services/storage/storage.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

BangumiItem _item(int id) => BangumiItem(
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
);

class _DelayedPopular extends PopularController {
  Completer<List<BangumiItem>>? request;
  int requests = 0;

  Future<void> _load(ObservableList<BangumiItem> items) async {
    requests++;
    final pending = request = Completer<List<BangumiItem>>();
    runInAction(() => isLoadingMore = true);
    final result = await pending.future;
    runInAction(() {
      // Mutate the same list, just like the real controller's HTTP completion.
      items.addAll(result);
      isLoadingMore = false;
      isTimeOut = items.isEmpty;
    });
  }

  @override
  Future<void> queryBangumiByTrend({String type = 'add'}) => _load(trendList);
  @override
  Future<void> queryBangumiByTag({String type = 'add'}) => _load(bangumiList);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform originalPaths;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp(
      'kazumi_popular_loading_',
    );
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = originalPaths;
    await directory.delete(recursive: true);
  });

  testWidgets('recommendation posters reflow and open the selected title', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1032, 1376);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final messenger = tester.binding.defaultBinaryMessenger;
    const channel = EventChannel('com.predidit.kazumi/scene');
    late MockStreamHandlerEventSink scene;
    messenger.setMockStreamHandler(
      channel,
      MockStreamHandler.inline(
        onListen: (_, events) {
          scene = events;
        },
      ),
    );
    final controller = _DelayedPopular();
    final titles = List.generate(24, (index) => _item(index + 1));
    controller.trendList.addAll(titles);
    BangumiItem? selected;
    final scale = ValueNotifier(1.0);
    addTearDown(scale.dispose);
    try {
      await tester.pumpWidget(
        ModularApp(
          module: createModule(
            register: (routes) {
              routes.route(
                '/',
                child: (_, _) => PopularPage(controller: controller),
              );
              routes.route(
                '/info/',
                child: (_, state) {
                  selected = state.arguments as BangumiItem;
                  return Text('详情：${selected!.nameCn}');
                },
              );
            },
          ),
          child: Builder(
            builder: (context) => MaterialApp.router(
              routerConfig: ModularApp.routerConfigOf(context),
              builder: (context, child) => ValueListenableBuilder<double>(
                valueListenable: scale,
                builder: (context, value, _) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(value)),
                  child: IosSceneEnvironment(child: child!),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<int> firstRow(
        Size size, {
        bool isPad = true,
        double textScale = 1,
      }) async {
        tester.view.physicalSize = size;
        scale.value = textScale;
        scene.success({
          'isPad': isPad,
          'width': size.width,
          'height': size.height,
        });
        await tester.pumpAndSettle();
        final cards = find.byType(BangumiCardV);
        final top = tester.getTopLeft(cards.first).dy;
        final rows = cards.evaluate().map(
          (element) => tester.getTopLeft(find.byWidget(element.widget)).dy,
        );
        expect(rows.any((y) => y > top), isTrue);
        return rows.where((y) => (y - top).abs() < .01).length;
      }

      expect(await firstRow(const Size(1032, 1376)), 4);
      expect(await firstRow(const Size(1376, 1032)), 5);
      expect(await firstRow(const Size(700, 1032)), 3);
      expect(await firstRow(const Size(375, 1032)), 2);
      expect(await firstRow(const Size(1032, 1376), textScale: 2), lessThan(4));
      expect(await firstRow(const Size(393, 852), isPad: false), 2);
      expect(await firstRow(const Size(951, 669), isPad: false), 6);
      expect(await firstRow(const Size(1032, 1376)), 4);
      await tester.tap(find.byType(BangumiCardV).at(3));
      await tester.pumpAndSettle();
      expect(selected, same(titles[3]));
      expect(find.text('详情：番组4'), findsOneWidget);
      expect(controller.requests, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      messenger.setMockStreamHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('first response shows posters without navigation or resizing', (
    tester,
  ) async {
    final controller = _DelayedPopular();
    await tester.pumpWidget(
      MaterialApp(home: PopularPage(controller: controller)),
    );
    expect(controller.requests, 1);
    expect(find.byType(BangumiCardV), findsNothing);
    controller.request!.complete([_item(1), _item(2)]);
    await tester.pumpAndSettle();
    expect(find.text('番组1'), findsOneWidget);
    expect(find.text('番组2'), findsOneWidget);
    expect(controller.requests, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pagination rebuilds the existing grid after an in-place append',
    (tester) async {
      final controller = _DelayedPopular();
      controller.trendList.add(_item(1));
      await tester.pumpWidget(
        MaterialApp(home: PopularPage(controller: controller)),
      );
      final request = controller.queryBangumiByTrend();
      await tester.pump();
      controller.request!.complete([_item(2)]);
      await request;
      await tester.pumpAndSettle();
      expect(find.text('番组1'), findsOneWidget);
      expect(find.text('番组2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tag results render when their async request completes', (
    tester,
  ) async {
    final controller = _DelayedPopular();
    controller.trendList.add(_item(1));
    controller.currentTag = '科幻';
    await tester.pumpWidget(
      MaterialApp(home: PopularPage(controller: controller)),
    );
    final request = controller.queryBangumiByTag();
    await tester.pump();
    controller.request!.complete([_item(3)]);
    await request;
    await tester.pumpAndSettle();
    expect(find.text('番组3'), findsOneWidget);
    expect(find.text('番组1'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
