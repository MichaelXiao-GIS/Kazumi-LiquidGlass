import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/loading_indicator.dart';
import 'package:kazumi/modules/plugin/plugin_http_module.dart';
import 'package:kazumi/pages/plugin_editor/plugin_catalog_view.dart';
import 'package:kazumi/plugins/plugins_controller.dart';

class _CatalogController extends PluginsController {
  _CatalogController(PluginCatalogLoader loader) : super(catalogLoader: loader);

  @override
  String get ruleRepository => 'https://example.test';
}

void main() {
  testWidgets('catalog keeps cached rules visible while refreshing', (
    tester,
  ) async {
    final nextCatalog = Completer<List<PluginHTTPItem>>();
    PluginHTTPItem item(String name) => PluginHTTPItem(
      name: name,
      version: '1',
      author: '',
      lastUpdate: 0,
      useNativePlayer: true,
    );
    var requests = 0;
    final controller = _CatalogController((_) async {
      requests++;
      return requests == 1 ? [item('已缓存规则')] : nextCatalog.future;
    });
    await controller.ensurePluginCatalog();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PluginCatalogView(controller: controller)),
      ),
    );
    final refresh = find.byTooltip('刷新规则列表');
    await tester.tap(refresh);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final loading = find.byTooltip('正在加载规则列表');
    expect(find.text('已缓存规则'), findsOneWidget);
    expect(
      find.descendant(of: loading, matching: find.byType(LoadingIndicator)),
      findsOneWidget,
    );
    await tester.tap(loading);
    expect(requests, 2);
    nextCatalog.complete([item('更新后的规则')]);
    await tester.pumpAndSettle();
    expect(refresh, findsOneWidget);
    expect(loading, findsNothing);
    expect(find.text('更新后的规则'), findsOneWidget);
  });
}
