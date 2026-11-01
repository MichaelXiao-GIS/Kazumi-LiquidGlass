import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/player/player_glass_controls.dart';
import 'package:kazumi/pages/player/player_gesture_detector.dart';
import 'package:kazumi/pages/player/player_panel_hold.dart';
import 'package:kazumi/pages/video/video_viewport_geometry.dart';

class _PlayerHarness extends StatefulWidget {
  const _PlayerHarness({super.key});

  @override
  State<_PlayerHarness> createState() => _PlayerHarnessState();
}

class _PlayerHarnessState extends State<_PlayerHarness> {
  bool visible = false;
  bool playing = true;
  int holds = 0;
  int seeks = 0;
  int episodes = 0;

  void togglePlayback() => setState(() => playing = !playing);

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: ThemeData(platform: TargetPlatform.iOS),
    home: Scaffold(
      body: VideoViewportScope(
        geometry: const VideoViewportGeometry(
          size: Size(800, 500),
          padding: EdgeInsets.zero,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => visible = !visible),
              onDoubleTap: togglePlayback,
              child: const ColoredBox(color: Colors.black),
            ),
            if (visible)
              PlayerPanelHoldMouseRegion(
                acquirePlayerPanelHold: () {
                  holds++;
                  return PlayerPanelHold(onRelease: () => holds--);
                },
                child: PlayerGlassControls(
                  fillsWindow: true,
                  title: '测试番剧 [01]',
                  back: const SizedBox(width: 44),
                  more: IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.more_horiz),
                  ),
                  onEpisodes: () => episodes++,
                  playPause: IconButton(
                    tooltip: '播放或暂停',
                    onPressed: togglePlayback,
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  ),
                  nextEpisode: const SizedBox(width: 44),
                  progress: Slider(value: .4, onChanged: (_) => seeks++),
                  time: const Text('00:11 / 24:21'),
                  danmaku: const SizedBox(width: 44),
                  speed: const SizedBox(width: 44),
                  fullscreen: const SizedBox(width: 44),
                  unlock: const SizedBox(width: 44),
                ),
              ),
            // The real player keeps drag recognition above the control layer.
            Positioned.fill(
              left: 16,
              top: 25,
              right: 15,
              bottom: 15,
              child: PlayerGestureDetector(
                onSeekStart: () {},
                onSeekUpdate: (_, _) {},
                onSeekEnd: (_) {},
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  Future<_PlayerHarnessState> mount(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 500);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final key = GlobalKey<_PlayerHarnessState>();
    await tester.pumpWidget(_PlayerHarness(key: key));
    return key.currentState!;
  }

  Future<void> tapVideo(WidgetTester tester) async {
    await tester.tapAt(const Offset(400, 250));
    await tester.pumpAndSettle(const Duration(milliseconds: 350));
  }

  Future<void> doubleTapVideo(WidgetTester tester) async {
    await tester.tapAt(const Offset(400, 250));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(const Offset(400, 250));
    await tester.pumpAndSettle(const Duration(milliseconds: 350));
  }

  testWidgets('video taps repeatedly show and hide all glass controls', (
    tester,
  ) async {
    final state = await mount(tester);
    for (var cycle = 0; cycle < 3; cycle++) {
      await tapVideo(tester);
      expect(state.visible, isTrue);
      expect(find.byKey(const ValueKey('glass-player-dock')), findsOneWidget);
      await tapVideo(tester);
      expect(state.visible, isFalse);
      expect(find.byType(PlayerGlassSurface), findsNothing);
    }
    expect(state.playing, isTrue);
  });

  testWidgets('double tap pauses and resumes with controls shown or hidden', (
    tester,
  ) async {
    final state = await mount(tester);
    for (final visible in [false, true]) {
      if (visible) await tapVideo(tester);
      await doubleTapVideo(tester);
      expect(state.playing, isFalse);
      expect(state.visible, visible);
      await doubleTapVideo(tester);
      expect(state.playing, isTrue);
      expect(state.visible, visible);
    }
  });

  testWidgets('control buttons and seek bar do not toggle the video overlay', (
    tester,
  ) async {
    final state = await mount(tester);
    await tapVideo(tester);
    await tester.tap(find.byTooltip('播放或暂停'));
    await tester.pumpAndSettle();
    expect(state.playing, isFalse);
    expect(state.visible, isTrue);
    await tester.tap(find.text('选集'));
    await tester.tap(find.byType(Slider));
    await tester.pumpAndSettle();
    expect(state.episodes, 1);
    expect(state.seeks, greaterThan(0));
    expect(state.visible, isTrue);
  });

  testWidgets('empty video does not acquire a control hover hold', (
    tester,
  ) async {
    final state = await mount(tester);
    await tapVideo(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(400, 250));
    await tester.pump();
    expect(state.holds, 0);
    await mouse.moveTo(tester.getCenter(find.text('选集')));
    await tester.pump();
    expect(state.holds, 1);
    await mouse.moveTo(const Offset(400, 250));
    await tester.pump();
    expect(state.holds, 0);
    await mouse.removePointer();
  });
}
