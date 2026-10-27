import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/bangumi_tag.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/pages/info/info_page.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/repositories/collect_crud_repository.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/theme.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _InfoController extends InfoController {
  _InfoController(super.collectController);
  @override
  Future<void> queryBangumiCharactersByID(int id) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform originalPaths;
  late CollectController collection;
  late ModularBootstrap bootstrap;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('kazumi_info_watch_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
    collection = CollectController(CollectCrudRepository());
    bootstrap = bootstrapModule(
      createModule(
        register: (c) {
          c.addInstance<CollectController>(collection);
        },
      ),
    );
  });
  tearDownAll(() async {
    bootstrap.injector.dispose();
    await Hive.close();
    PathProviderPlatform.instance = originalPaths;
    await directory.delete(recursive: true);
  });

  for (final size in [const Size(390, 844), const Size(900, 650)]) {
    testWidgets('watch button shrinks on scroll and expands at top: $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final item = BangumiItem(
        id: 1,
        type: 2,
        name: '测试番剧',
        nameCn: '测试番剧',
        summary: List.filled(20, '这是用来测试详情页滚动的简介。').join('\n'),
        airDate: '2026-10-01',
        airWeekday: 1,
        rank: 1,
        images: {},
        tags: List.generate(
          12,
          (i) => BangumiTag(name: '详情标签$i', count: i, totalCount: i),
        ),
        alias: [],
        ratingScore: 8,
        votes: 10,
        votesCount: List.filled(10, 1),
        info: '',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: iosAppTheme(ThemeData()),
          home: InfoPage(
            inputBangumiItem: item,
            infoController: _InfoController(collection),
            pluginsController: PluginsController(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.byType(FloatingActionButton);
      final initialRect = tester.getRect(button);
      expect(find.text('开始观看'), findsOneWidget);
      expect(initialRect.width, greaterThan(initialRect.height));

      final start = Offset(size.width / 2, size.height * .7);
      await tester.dragFrom(start, const Offset(0, -350));
      await tester.pumpAndSettle();
      final compactRect = tester.getRect(button);
      expect(find.text('开始观看'), findsNothing);
      expect(find.byTooltip('开始观看'), findsOneWidget);
      expect(compactRect.size, const Size(56, 56));
      expect(compactRect.right, closeTo(initialRect.right, .1));
      expect(
        find.descendant(
          of: button,
          matching: find.byIcon(Icons.play_arrow_rounded),
        ),
        findsOneWidget,
      );

      // A horizontal page change must not expand the action over the content.
      await tester.tap(find.text('角色'));
      await tester.pumpAndSettle();
      expect(tester.getSize(button), const Size(56, 56));
      await tester.tap(find.text('概览'));
      await tester.pumpAndSettle();
      await tester.dragFrom(start, const Offset(0, 1000));
      await tester.pumpAndSettle();
      expect(find.text('开始观看'), findsOneWidget);
      expect(tester.getSize(button), initialRect.size);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
