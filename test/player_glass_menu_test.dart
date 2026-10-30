import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/kazumi_menu.dart';
import 'package:kazumi/pages/player/player_glass_controls.dart';
import 'package:kazumi/pages/player/player_panel_hold.dart';

void main() {
  testWidgets('glass menu animates both ways and has no inset scrollbar', (
    tester,
  ) async {
    var released = 0;
    final visibility = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(678, 466),
            padding: EdgeInsets.only(right: 80),
          ),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: SizedBox(
                width: 44,
                height: 44,
                child: PlayerGlassSurface(
                  child: PlayerPanelHoldMenuAnchor(
                    animated: true,
                    hideScrollIndicator: true,
                    acquirePlayerPanelHold: () =>
                        PlayerPanelHold(onRelease: () => released++),
                    onVisibilityChanged: visibility.add,
                    builder: (_, toggle) => IconButton(
                      onPressed: toggle,
                      tooltip: '更多',
                      icon: const Icon(Icons.more_horiz),
                    ),
                    menuChildren: [
                      for (var i = 0; i < 20; i++)
                        KazumiMenuItem(label: '操作 $i', onPressed: () {}),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('更多'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final fade = tester
        .widgetList<FadeTransition>(find.byType(FadeTransition))
        .where((w) => w.opacity.value > 0 && w.opacity.value < 1);
    expect(fade, isNotEmpty);
    await tester.pumpAndSettle();
    final scrollbarContext = tester.element(find.byType(Scrollbar).last);
    expect(ScrollbarTheme.of(scrollbarContext).thickness!.resolve({}), 0);
    expect(find.byType(CupertinoScrollbar), findsNothing);
    await tester.tap(find.text('操作 0'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      tester
          .widgetList<FadeTransition>(find.byType(FadeTransition))
          .any((w) => w.opacity.value > 0 && w.opacity.value < 1),
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(visibility, [true, false]);
    expect(released, 1);
    expect(find.text('操作 0'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
