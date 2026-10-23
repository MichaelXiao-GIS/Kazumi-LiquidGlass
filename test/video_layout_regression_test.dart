import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/video/video_fullscreen_controller.dart';
import 'package:kazumi/pages/video/video_page_layout.dart';
import 'package:kazumi/pages/video/video_side_panel.dart';

class _PlayingSurface extends StatefulWidget {
  const _PlayingSurface({required this.onStart, required this.onDispose});
  final VoidCallback onStart;
  final VoidCallback onDispose;

  @override
  State<_PlayingSurface> createState() => _PlayingSurfaceState();
}

class _PlayingSurfaceState extends State<_PlayingSurface> {
  @override
  void initState() {
    super.initState();
    widget.onStart();
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.red);
}

void main() {
  testWidgets('unfolded phone keeps a full-height video beside episode tabs', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(951, 669);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(padding: const EdgeInsets.only(right: 80, bottom: 34)),
          child: child!,
        ),
        home: Scaffold(
          body: VideoPageLayout(
            fullscreen: false,
            isPip: false,
            playerBuilder: (_, _) =>
                const ColoredBox(key: ValueKey('video'), color: Colors.black),
            tabs: const SizedBox.expand(key: ValueKey('episodes')),
          ),
        ),
      ),
    );
    final video = tester.getRect(find.byKey(const ValueKey('video')));
    final episodes = tester.getRect(find.byKey(const ValueKey('episodes')));
    expect(video.topLeft, Offset.zero);
    expect(video.bottom, 669);
    expect(episodes.left, video.right);
    expect(episodes.top, 0);
    expect(episodes.bottom, 635);
    expect(episodes.right, 871);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide playback paints black through bottom and camera insets', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 700);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    EdgeInsets? controlsInsets;
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('screen'),
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(padding: const EdgeInsets.fromLTRB(40, 24, 0, 34)),
            child: child!,
          ),
          home: Scaffold(
            body: VideoPageLayout(
              fullscreen: false,
              isPip: false,
              playerBuilder: (context, _) {
                controlsInsets = MediaQuery.paddingOf(context);
                return const ColoredBox(color: Colors.black);
              },
              tabs: const Text('选集'),
            ),
          ),
        ),
      ),
    );
    expect(controlsInsets, const EdgeInsets.fromLTRB(40, 24, 0, 34));
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('screen')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      for (final point in [const Offset(1, 1), const Offset(500, 699)]) {
        expect(
          pixels.getUint32(
            (point.dy.toInt() * image.width + point.dx.toInt()) * 4,
          ),
          0x000000ff,
        );
      }
      image.dispose();
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'playing surface survives fullscreen, sidebar and back navigation',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(951, 669);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fullscreen = VideoFullscreenController(
        applyFullscreen: (_) async {},
      );
      final sidebar = GlobalKey<VideoSidePanelState>();
      final episodes = GlobalKey();
      var started = 0;
      var disposed = 0;
      late BuildContext routeContext;
      Widget tabs() =>
          SizedBox.expand(key: episodes, child: const Text('第 3 集'));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              routeContext = context;
              fullscreen.attach(ModalRoute.of(context)!);
              return Observer(
                builder: (_) => Scaffold(
                  body: VideoPageLayout(
                    fullscreen: fullscreen.isFullscreen,
                    isPip: false,
                    playerBuilder: (_, _) => _PlayingSurface(
                      onStart: () => started++,
                      onDispose: () => disposed++,
                    ),
                    tabs: tabs(),
                    sidePanel: VideoSidePanel(
                      key: sidebar,
                      fullscreen: fullscreen.isFullscreen,
                      child: tabs(),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      for (var i = 0; i < 3; i++) {
        await fullscreen.toggle();
        await tester.pumpAndSettle();
        final layout = find.byType(VideoPageLayout);
        expect(tester.getSize(layout), const Size(951, 669));
        expect(
          tester.getSize(find.byType(_PlayingSurface)),
          const Size(951, 669),
        );
        expect(
          find.byType(_PlayingSurface).hitTestable(at: Alignment.center),
          findsOneWidget,
        );
        expect(find.text('第 3 集'), findsNothing);
        sidebar.currentState!.toggle();
        await tester.pumpAndSettle();
        expect(find.text('第 3 集'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (i.isEven) {
          sidebar.currentState!.close();
          await tester.pumpAndSettle();
        }
        await Navigator.of(routeContext).maybePop();
        await tester.pumpAndSettle();
        expect(fullscreen.isFullscreen, isFalse);
        expect(find.text('第 3 集'), findsOneWidget);
        expect(started, 1);
        expect(disposed, 0);
        expect(tester.takeException(), isNull);
      }
      await fullscreen.close();
    },
  );
}
