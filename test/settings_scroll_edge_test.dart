import 'dart:io';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/settings/settings_list.dart';
import 'package:kazumi/bean/widget/ios_bottom_scrim.dart';
import 'package:kazumi/pages/about/about_widgets.dart';
import 'package:kazumi/pages/settings/sync/sync_settings_widgets.dart';
import 'package:kazumi/utils/theme.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
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

  for (final size in [const Size(466, 678), const Size(951, 669)]) {
    for (final kind in ['settings', 'sync', 'about']) {
      testWidgets(
        '$kind scrolls behind home area and clears last action: $size',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          var taps = 0;
          final content = [
            const SizedBox(
              width: double.infinity,
              height: 2000,
              child: ColoredBox(color: Color(0xffd54162)),
            ),
            TextButton(
              key: const ValueKey('last'),
              onPressed: () => taps++,
              child: const Text('最后一个设置项'),
            ),
          ];
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('window'),
              child: MaterialApp(
                theme: iosAppTheme(ThemeData()),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    padding: const EdgeInsets.only(right: 80, bottom: 34),
                    viewPadding: const EdgeInsets.only(right: 80, bottom: 34),
                  ),
                  child: child!,
                ),
                home: SettingsDetailScaffold(
                  title: const Text('设置'),
                  body: switch (kind) {
                    'sync' => SyncPageBody(children: content),
                    'about' => AboutContent(children: content),
                    _ => SettingsList(sections: content),
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final scrollable = tester.state<ScrollableState>(
            find.byType(Scrollable),
          );
          expect(tester.getRect(find.byType(Scrollable)).bottom, size.height);
          expect(find.byType(IosBottomScrim), findsOneWidget);
          scrollable.position.jumpTo(200);
          await tester.pumpAndSettle();
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('window')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            for (var y = size.height.toInt() - 34; y < size.height; y++) {
              final index = (y * image.width + 200) * 4;
              expect(
                bytes.getUint8(index) - bytes.getUint8(index + 1),
                greaterThan(20),
                reason:
                    'Content must remain visible through the home-area material',
              );
            }
            image.dispose();
          });
          scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
          await tester.pumpAndSettle();
          expect(
            tester.getRect(find.byKey(const ValueKey('last'))).bottom,
            lessThanOrEqualTo(size.height - 34),
          );
          await tester.tap(find.byKey(const ValueKey('last')));
          expect(taps, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
