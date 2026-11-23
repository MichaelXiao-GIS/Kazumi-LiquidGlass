import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/player/controller/player_screenshot_controller.dart';
import 'package:kazumi/pages/player/player_screenshot_sheet.dart';
import 'package:kazumi/services/platform/photo_gallery.dart';

void main() {
  testWidgets('a second photo waits for the first native save callback', (
    tester,
  ) async {
    final firstSave = Completer<void>();
    final names = <String>[];
    const channel = MethodChannel('com.fluttercandies/saver_gallery');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      names.add(call.arguments['fileName'] as String);
      if (names.length == 1) await firstSave.future;
      return {'isSuccess': true};
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final bytes = base64Decode('iVBORw0KGgo=');
    final first = savePngToGallery(bytes, 'first.png');
    final second = savePngToGallery(bytes, 'second.png');
    await tester.pump();
    expect(names, ['first.png']);
    firstSave.complete();
    await tester.pump();
    expect((await first).isSuccess, isTrue);
    expect((await second).isSuccess, isTrue);
    expect(names, ['first.png', 'second.png']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('narrow iOS picker retries only photos that failed to save', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 580));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = PlayerScreenshotController();
    addTearDown(controller.dispose);
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8'
      '/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
    );
    for (final second in [1, 2]) {
      await controller.capture(
        capturePng: () async => png,
        title: '番剧',
        episode: '第一集',
        position: Duration(seconds: second),
        isCurrent: () => true,
      );
    }
    final savedNames = <String>[];
    const channel = MethodChannel('com.fluttercandies/saver_gallery');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'saveImageToGallery');
      final args = call.arguments as Map;
      expect(args['image'], orderedEquals(png));
      expect(args['extension'], 'png');
      savedNames.add(args['fileName'] as String);
      final success = savedNames.length != 2;
      return {'isSuccess': success, 'errorMessage': success ? null : 'denied'};
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showPlayerScreenshotSheet(context, controller: controller),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('存入相册（2 张）'));
    await tester.pumpAndSettle();
    expect(savedNames, hasLength(2));
    expect(controller.selectedCount, 1);
    expect(controller.candidates, hasLength(1));
    expect(
      find.text('已保存 1 张，1 张失败；未保存的截图仍已选中，请重试。可检查系统相册的写入权限'),
      findsOneWidget,
    );
    for (final size in [const Size(951, 669), const Size(844, 390)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpAndSettle();
      expect(find.text('存入相册（1 张）').hitTestable(), findsOneWidget);
      expect(find.text('已选中').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.text('存入相册（1 张）'));
    await tester.pumpAndSettle();
    expect(savedNames, hasLength(3));
    expect(savedNames[0], isNot(savedNames[1]));
    expect(savedNames[2], savedNames[1]);
    expect(controller.candidates, isEmpty);
    expect(find.text('暂无待处理截图'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('thumbnail gestures select independently of browsing and zoom', (
    tester,
  ) async {
    final controller = PlayerScreenshotController();
    addTearDown(controller.dispose);
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8'
      '/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
    );
    for (final second in [1, 2]) {
      await controller.capture(
        capturePng: () async => png,
        title: '测试',
        episode: 'EP1',
        position: Duration(seconds: second),
        isCurrent: () => true,
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showPlayerScreenshotSheet(context, controller: controller),
              child: const Text('打开截图'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开截图'));
    await tester.pumpAndSettle();

    final thumbnail = find.bySemanticsLabel(RegExp('查看第 1 张'));
    final pages = tester.widget<PageView>(find.byType(PageView)).controller!;
    final first = controller.candidates.first;

    Future<void> doubleTap(Finder target) async {
      await tester.tap(target);
      await tester.pump(kDoubleTapMinTime + const Duration(milliseconds: 10));
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    expect(pages.page, 1);
    for (final selected in [true, false]) {
      await doubleTap(thumbnail);
      expect(controller.isSelected(first), selected);
      expect(pages.page, 1);
    }
    await tester.tap(thumbnail);
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
    expect(pages.page, 0);
    final preview = find.byKey(ValueKey(first.id));
    await doubleTap(preview);
    final viewer = tester.widget<InteractiveViewer>(
      find.descendant(of: preview, matching: find.byType(InteractiveViewer)),
    );
    expect(
      viewer.transformationController!.value.getMaxScaleOnAxis(),
      greaterThan(1),
    );
    expect(controller.selectedCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
