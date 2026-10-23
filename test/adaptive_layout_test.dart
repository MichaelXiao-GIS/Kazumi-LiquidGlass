import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/ios_glass.dart';
import 'package:kazumi/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:kazumi/bean/widget/ios_scene_environment.dart';
import 'package:kazumi/pages/menu/adaptive_navigation_scaffold.dart';
import 'package:kazumi/pages/video/video_page_layout.dart';
import 'package:kazumi/utils/adaptive_layout.dart';
import 'package:kazumi/utils/theme.dart';

class _PlaybackProbe extends StatefulWidget {
  const _PlaybackProbe({required this.onInit, required this.onDispose});
  final VoidCallback onInit;
  final VoidCallback onDispose;
  @override
  State<_PlaybackProbe> createState() => _PlaybackProbeState();
}

class _PlaybackProbeState extends State<_PlaybackProbe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Colors.black,
    child: Center(child: Text('正在播放 第 8 集')),
  );
}

void main() {
  testWidgets(
    'iOS header has no visible separator in light and dark appearances',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 650);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('seam'),
            child: MaterialApp(
              theme: iosAppTheme(ThemeData(brightness: brightness)),
              home: AdaptiveNavigationScaffold(
                selectedIndex: 0,
                onSelected: (_) {},
                onSearch: () {},
                child: Scaffold(
                  appBar: AppBar(),
                  body: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('seam')),
        );
        await tester.runAsync(() async {
          final snapshot = await boundary.toImage(pixelRatio: 1);
          final bytes = (await snapshot.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          int pixel(int y) => bytes.getUint32((y * snapshot.width + 700) * 4);
          final background = pixel(80);
          for (var y = 50; y <= 64; y++) {
            expect(
              pixel(y),
              background,
              reason: 'No border or tint seam at row $y in $brightness',
            );
          }
          snapshot.dispose();
        });
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'header spans the window including navigation and camera gutters',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 650);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: iosAppTheme(ThemeData()),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(padding: const EdgeInsets.only(left: 64, right: 24)),
            child: child!,
          ),
          home: AdaptiveNavigationScaffold(
            selectedIndex: 0,
            onSelected: (_) {},
            onSearch: () {},
            child: Scaffold(
              appBar: AppBar(key: const ValueKey('test-header')),
              body: const SizedBox.expand(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final header = find.byType(AppBar);
      expect(tester.getRect(header), const Rect.fromLTWH(0, 0, 900, 56));
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(tester.getRect(header), const Rect.fromLTWH(0, 0, 390, 56));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('full width header follows the collapsing app bar', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 650);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: iosAppTheme(ThemeData()),
        home: AdaptiveNavigationScaffold(
          selectedIndex: 0,
          onSelected: (_) {},
          onSearch: () {},
          child: Scaffold(
            body: CustomScrollView(
              controller: scroll,
              slivers: const [
                SliverAppBar(pinned: true, expandedHeight: 120),
                SliverToBoxAdapter(child: SizedBox(height: 1600)),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final header = find.byType(AppBar);
    expect(tester.getRect(header), const Rect.fromLTWH(0, 0, 900, 120));
    scroll.jumpTo(200);
    await tester.pumpAndSettle();
    expect(tester.getRect(header), const Rect.fromLTWH(0, 0, 900, 56));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'book fold keeps video and episode controls clear of the crease',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 650);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              displayFeatures: const [
                ui.DisplayFeature(
                  bounds: Rect.fromLTWH(450, 0, 16, 650),
                  type: ui.DisplayFeatureType.fold,
                  state: ui.DisplayFeatureState.postureHalfOpened,
                ),
              ],
            ),
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
      expect(
        tester.getBottomRight(find.byKey(const ValueKey('video'))).dx,
        450,
      );
      expect(tester.getTopLeft(find.byKey(const ValueKey('episodes'))).dx, 466);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('shared sheets open on one side of an active fold', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 650);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            displayFeatures: const [
              ui.DisplayFeature(
                bounds: Rect.fromLTWH(450, 0, 16, 650),
                type: ui.DisplayFeatureType.fold,
                state: ui.DisplayFeatureState.postureHalfOpened,
              ),
            ],
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAdaptiveBottomSheet<void>(
                context: context,
                builder: (_) => const SizedBox(
                  height: 180,
                  width: double.infinity,
                  key: ValueKey('sheet'),
                  child: Text('选集'),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('sheet'))).dx,
      greaterThanOrEqualTo(466),
    );
    expect(tester.takeException(), isNull);
  });

  test('layout decisions follow available space, including short windows', () {
    expect(AdaptiveLayout.useSideNavigation(const Size(390, 844)), isFalse);
    expect(AdaptiveLayout.useSideNavigation(const Size(760, 900)), isTrue);
    expect(AdaptiveLayout.useSideNavigation(const Size(320, 600)), isFalse);
    expect(AdaptiveLayout.useSideNavigation(const Size(800, 280)), isFalse);
    expect(AdaptiveLayout.usePlayerColumns(const Size(900, 650)), isTrue);
    expect(
      AdaptiveLayout.playerFillsWindow(
        const Size(900, 650),
        fullscreen: false,
        isPip: false,
      ),
      isFalse,
    );
    expect(
      AdaptiveLayout.playerFillsWindow(
        const Size(844, 390),
        fullscreen: false,
        isPip: false,
      ),
      isTrue,
    );
  });

  test('poster density uses the pane width and accommodates large text', () {
    expect(AdaptiveLayout.posterColumns(350, TextScaler.noScaling), 2);
    expect(AdaptiveLayout.posterColumns(710, TextScaler.noScaling), 4);
    expect(AdaptiveLayout.posterColumns(710, const TextScaler.linear(2)), 2);
    expect(AdaptiveLayout.posterColumns(160, TextScaler.noScaling), 1);
  });

  test(
    'scene regions are in logical points and stale pose data is rejected',
    () {
      final scene = IosSceneData.fromMap({
        'width': 760,
        'height': 900,
        'occlusions': [
          [704, 0, 56, 180],
        ],
        'divisions': [
          [0, 450, 760, 0],
        ],
        'reduceTransparency': true,
      });
      expect(scene.matches(const Size(760, 900)), isTrue);
      expect(scene.matches(const Size(390, 844)), isFalse);
      expect(scene.reduceTransparency, isTrue);
      expect(
        AdaptiveLayout.horizontalDivision(scene.size, scene.divisions),
        const Rect.fromLTWH(0, 450, 760, 0),
      );
    },
  );

  testWidgets(
    'folding keeps the outlet mounted and changes navigation placement',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var started = 0;
      var disposed = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: iosAppTheme(ThemeData()),
          home: AdaptiveNavigationScaffold(
            selectedIndex: 2,
            onSelected: (_) {},
            onSearch: () {},
            child: _PlaybackProbe(
              onInit: () => started++,
              onDispose: () => disposed++,
            ),
          ),
        ),
      );
      expect(
        tester
            .widget<IosGlassNavigation>(find.byType(IosGlassNavigation))
            .vertical,
        isFalse,
      );
      tester.view.physicalSize = const Size(900, 700);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IosGlassNavigation>(find.byType(IosGlassNavigation))
            .vertical,
        isTrue,
      );
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(started, 1);
      expect(disposed, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'safe areas are consumed once and narrow enlarged navigation fits',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      EdgeInsets? childPadding;
      Size? childSize;
      await tester.pumpWidget(
        MaterialApp(
          theme: iosAppTheme(ThemeData()),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              padding: const EdgeInsets.fromLTRB(24, 44, 12, 34),
            ),
            child: child!,
          ),
          home: AdaptiveNavigationScaffold(
            selectedIndex: 0,
            onSelected: (_) {},
            onSearch: () {},
            child: SafeArea(
              top: false,
              bottom: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  childPadding = MediaQuery.paddingOf(context);
                  childSize = constraints.biggest;
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(childPadding, const EdgeInsets.only(top: 44));
      expect(childSize, const Size(284, 426));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'expanded playback exposes episodes and survives fold/fullscreen',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var started = 0;
      var disposed = 0;
      VideoPlayerLayout? mode;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoPageLayout(
              fullscreen: false,
              isPip: false,
              playerBuilder: (context, layout) {
                mode = layout;
                return _PlaybackProbe(
                  onInit: () => started++,
                  onDispose: () => disposed++,
                );
              },
              tabs: const Center(child: Text('选集')),
            ),
          ),
        ),
      );
      expect(mode!.fillsWindow, isFalse);
      expect(
        tester.getCenter(find.text('选集')).dy,
        greaterThan(tester.getCenter(find.byType(_PlaybackProbe)).dy),
      );
      tester.view.physicalSize = const Size(900, 650);
      await tester.pumpAndSettle();
      expect(mode!.fillsWindow, isFalse);
      expect(
        tester.getCenter(find.text('选集')).dx,
        greaterThan(tester.getCenter(find.byType(_PlaybackProbe)).dx),
      );
      tester.view.physicalSize = const Size(844, 390);
      await tester.pumpAndSettle();
      expect(mode!.fillsWindow, isTrue);
      expect(find.text('选集'), findsNothing);
      expect(started, 1);
      expect(disposed, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tabletop keeps video and controls on opposite sides of the fold',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(760, 720);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              displayFeatures: const [
                ui.DisplayFeature(
                  bounds: Rect.fromLTWH(0, 340, 760, 16),
                  type: ui.DisplayFeatureType.fold,
                  state: ui.DisplayFeatureState.postureHalfOpened,
                ),
              ],
            ),
            child: child!,
          ),
          home: Scaffold(
            body: VideoPageLayout(
              fullscreen: false,
              isPip: false,
              playerBuilder: (_, _) =>
                  const ColoredBox(key: ValueKey('video'), color: Colors.black),
              tabs: const Center(child: Text('选集')),
            ),
          ),
        ),
      );
      expect(tester.getBottomLeft(find.byKey(const ValueKey('video'))).dy, 340);
      expect(tester.getTopLeft(find.text('选集')).dy, greaterThanOrEqualTo(356));
      expect(tester.takeException(), isNull);
    },
  );
}
