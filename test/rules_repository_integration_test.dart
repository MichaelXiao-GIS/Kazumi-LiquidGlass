import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/widget/ios_bottom_scrim.dart';
import 'package:kazumi/modules/plugin/plugin_http_module.dart';
import 'package:kazumi/pages/plugin_editor/plugin_shop_page.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/theme.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

PluginHTTPItem _catalogItem(String name) => PluginHTTPItem(
  name: name,
  version: '2.0',
  useNativePlayer: true,
  author: 'test',
  lastUpdate: 0,
);

Plugin _plugin(String name, {String version = '2.0'}) => Plugin.fromTemplate()
  ..name = name
  ..version = version;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform originalPaths;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp(
      'kazumi_rule_repository_',
    );
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });

  setUp(() async {
    await GStorage.putSetting(SettingsKeys.ruleRepositoryUrl, '');
  });

  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = originalPaths;
    await directory.delete(recursive: true);
  });

  test(
    'switching repositories detaches an in-flight catalog request',
    () async {
      final oldCatalog = Completer<List<PluginHTTPItem>>();
      final calls = <String>[];
      final controller = PluginsController(
        catalogLoader: (repository) {
          calls.add(repository);
          return repository.isEmpty
              ? oldCatalog.future
              : Future.value([_catalogItem('custom')]);
        },
      );
      final oldRequest = controller.refreshPluginCatalog();
      await controller.setRuleRepository(
        'https://example.com/rules/index.json',
      );
      await controller.refreshPluginCatalog();
      expect(calls, ['', 'https://example.com/rules/']);
      expect(controller.pluginHTTPList.single.name, 'custom');

      oldCatalog.complete([_catalogItem('obsolete')]);
      await oldRequest;
      expect(controller.pluginHTTPList.single.name, 'custom');
      expect(controller.isPluginCatalogFresh, isTrue);
    },
  );

  test(
    'a repository change clears its catalog but preserves installed rules',
    () async {
      final controller = PluginsController(
        catalogLoader: (_) async => [_catalogItem('installed')],
      );
      final installed = _plugin('installed', version: '1.0');
      controller.pluginList.add(installed);
      await controller.refreshPluginCatalog();

      expect(
        await controller.setRuleRepository('https://example.com/rules/'),
        isTrue,
      );
      expect(controller.pluginHTTPList, isEmpty);
      expect(controller.isPluginCatalogFresh, isFalse);
      expect(controller.pluginList.single, same(installed));
      expect(
        await controller.setRuleRepository(ApiEndpoints.pluginShop),
        isTrue,
      );
      expect(controller.ruleRepository, isEmpty);
      expect(controller.pluginList.single, same(installed));
    },
  );

  test('invalid or unchanged addresses preserve a valid catalog', () async {
    final controller = PluginsController(
      catalogLoader: (_) async => [_catalogItem('current')],
    );
    await controller.setRuleRepository('https://example.com/rules/');
    await controller.refreshPluginCatalog();
    await expectLater(
      controller.setRuleRepository('file:///tmp/rules'),
      throwsFormatException,
    );
    expect(
      await controller.setRuleRepository(
        'https://example.com/rules/index.json',
      ),
      isFalse,
    );
    expect(controller.ruleRepository, 'https://example.com/rules/');
    expect(controller.pluginHTTPList.single.name, 'current');
    expect(controller.isPluginCatalogFresh, isTrue);
  });

  test(
    'queued rule downloads keep the repository selected when requested',
    () async {
      final firstStarted = Completer<void>();
      final firstDownload = Completer<Plugin>();
      final sources = <String>[];
      final controller = PluginsController(
        pluginLoader: (repository, name) async {
          sources.add(repository);
          if (name == 'first') {
            firstStarted.complete();
            return firstDownload.future;
          }
          return _plugin(name);
        },
        pluginJsonWriter: (_) async {},
      );
      await controller.setRuleRepository('https://example.com/a/');
      final first = controller.tryUpdatePluginByName('first');
      await firstStarted.future;
      final queued = controller.tryUpdatePluginByName('second');
      await controller.setRuleRepository('https://example.com/b/');
      firstDownload.complete(_plugin('first'));

      expect(await first, PluginUpdateResult.updated);
      expect(await queued, PluginUpdateResult.updated);
      expect(sources, ['https://example.com/a/', 'https://example.com/a/']);
      expect(controller.pluginList.map((rule) => rule.name), [
        'first',
        'second',
      ]);
      expect(controller.ruleRepository, 'https://example.com/b/');
    },
  );

  for (final textScale in [1.0, 2.0]) {
    testWidgets(
      'repository editor survives Duo resizing at text scale $textScale',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(466, 678);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        var catalogLoads = 0;
        final controller = PluginsController(
          catalogLoader: (_) async {
            catalogLoads++;
            return [_catalogItem('test rule')];
          },
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: iosAppTheme(ThemeData()),
            navigatorObservers: [KazumiDialog.observer],
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding: const EdgeInsets.only(top: 24, right: 80, bottom: 34),
                viewPadding: const EdgeInsets.only(
                  top: 24,
                  right: 80,
                  bottom: 34,
                ),
                textScaler: TextScaler.linear(textScale),
              ),
              child: child!,
            ),
            home: SettingsPaneScope(
              embedded: true,
              showBackButton: false,
              onBack: () {},
              child: PluginShopPage(controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(IosBottomScrim), findsOneWidget);
        expect(tester.getRect(find.byType(CustomScrollView)).bottom, 678);
        await tester.tap(find.byTooltip('规则仓库地址'));
        await tester.pumpAndSettle();
        final editor = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        );
        const draft = 'https://example.com/my-rules/';
        await tester.enterText(editor, draft);
        for (final size in [const Size(951, 669), const Size(466, 678)]) {
          tester.view.physicalSize = size;
          await tester.pumpAndSettle();
          expect(tester.widget<TextField>(editor).controller!.text, draft);
          final dialog = tester.getRect(find.byType(AlertDialog));
          expect(dialog.right, lessThanOrEqualTo(size.width - 80));
          expect(dialog.bottom, lessThanOrEqualTo(size.height - 34));
          expect(tester.takeException(), isNull);
        }
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(controller.ruleRepository, isEmpty);
        expect(catalogLoads, 1);
        expect(find.byType(IosBottomScrim), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
