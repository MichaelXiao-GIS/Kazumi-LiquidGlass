import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/player/controller/player_screenshot_controller.dart';
import 'package:kazumi/pages/player/player_screenshot_sheet.dart';

void main() {
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
