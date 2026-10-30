import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/ios_scene_environment.dart';
import 'package:kazumi/pages/player/player_glass_controls.dart';
import 'package:kazumi/pages/video/video_page_layout.dart';
import 'package:kazumi/pages/video/video_viewport_geometry.dart';

VideoViewportGeometry geometry(Size size, Rect camera, EdgeInsets padding) =>
    VideoViewportGeometry.fromScene(
      pane: Offset.zero & size,
      window: size,
      padding: padding,
      scene: IosSceneData(size: size, occlusions: [camera]),
    );

PlayerGlassControlLayout layout(VideoViewportGeometry geometry) =>
    PlayerGlassControlLayout(
      geometry: geometry,
      fillsWindow: true,
      actionsWidth: 116,
      topHeight: 44,
      dockHeight: 80,
    );

void main() {
  const size = Size(678, 466);
  final baseline = layout(
    const VideoViewportGeometry(size: size, padding: EdgeInsets.zero),
  );
  final poses = {
    'top-left': (
      const Rect.fromLTWH(0, 0, 80, 84),
      const EdgeInsets.only(left: 80),
    ),
    'top-right': (
      const Rect.fromLTWH(598, 0, 80, 84),
      const EdgeInsets.only(right: 80),
    ),
    'bottom-left': (
      const Rect.fromLTWH(0, 382, 80, 84),
      const EdgeInsets.only(left: 80),
    ),
    'bottom-right': (
      const Rect.fromLTWH(598, 382, 80, 84),
      const EdgeInsets.only(right: 80),
    ),
  };
  for (final pose in poses.entries) {
    test('${pose.key} camera only displaces overlapping controls', () {
      final (camera, padding) = pose.value;
      final result = layout(geometry(size, camera, padding));
      for (final rect in [result.title, result.actions, result.dock]) {
        expect(rect.overlaps(camera.inflate(7)), isFalse);
        expect(rect.left, greaterThanOrEqualTo(8));
        expect(rect.right, lessThanOrEqualTo(size.width - 8));
      }
      expect(result.title.overlaps(result.actions), isFalse);
      expect(result.dock.width, closeTo(baseline.dock.width, .01));
      if (pose.key.startsWith('top')) {
        expect(result.dock, baseline.dock);
      } else {
        expect(result.title, baseline.title);
        expect(result.actions, baseline.actions);
      }
      if (pose.key.endsWith('left')) {
        expect(
          pose.key.startsWith('top') ? result.title.left : result.dock.left,
          greaterThan(
            pose.key.startsWith('top')
                ? baseline.title.left
                : baseline.dock.left,
          ),
        );
      }
    });
  }

  test('ordinary iPhone and inner-screen docks stay centered', () {
    for (final viewport in [const Size(852, 393), const Size(951, 669)]) {
      final result = layout(
        VideoViewportGeometry(
          size: viewport,
          padding: const EdgeInsets.fromLTRB(44, 0, 44, 21),
        ),
      );
      expect(result.dock.center.dx, closeTo(viewport.width / 2, .001));
    }
  });

  test('episode pane below a localized camera uses full width', () {
    const viewport = Size(466, 678);
    final scene = IosSceneData(
      size: viewport,
      occlusions: [const Rect.fromLTWH(386, 0, 80, 160)],
    );
    final result = VideoViewportGeometry.fromScene(
      pane: const Rect.fromLTWH(0, 262, 466, 416),
      window: viewport,
      padding: const EdgeInsets.only(right: 80, bottom: 34),
      scene: scene,
    );
    expect(result.contentPadding, const EdgeInsets.only(bottom: 34));
    // Rotation can briefly deliver a scene with the previous viewport size.
    final stale = VideoViewportGeometry.fromScene(
      pane: const Rect.fromLTWH(0, 262, 466, 416),
      window: viewport,
      padding: const EdgeInsets.only(right: 80, bottom: 34),
      scene: const IosSceneData(size: Size(678, 466)),
    );
    expect(stale.contentPadding, const EdgeInsets.only(right: 80, bottom: 34));
  });

  testWidgets('portrait iOS video extends through the side safe area', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(466, 678);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(466, 678),
            padding: EdgeInsets.only(right: 80, bottom: 34),
          ),
          child: VideoPageLayout(
            fullscreen: false,
            isPip: false,
            playerBuilder: (_, _) =>
                const ColoredBox(key: ValueKey('video'), color: Colors.black),
            tabs: const Text('选集'),
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.byKey(const ValueKey('video')));
    expect(rect.left, 0);
    expect(rect.right, 466);
    expect(rect.height, closeTo(466 * 9 / 16, .01));
  });

  testWidgets('glass controls remain usable across poses and text sizes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var episodes = 0;
    var menu = 0;
    var pauses = 0;
    Widget button(String tooltip, VoidCallback callback) => IconButton(
      tooltip: tooltip,
      onPressed: callback,
      icon: const Icon(Icons.play_arrow),
    );
    for (final scale in [1.0, 2.0]) {
      for (final pose in poses.values) {
        final data = geometry(size, pose.$1, pose.$2);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(scale),
              ),
              child: VideoViewportScope(
                geometry: data,
                child: PlayerGlassControls(
                  fillsWindow: true,
                  title: '学生会也有洞！ [01]',
                  back: button('返回', () {}),
                  more: button('更多', () => menu++),
                  onEpisodes: () => episodes++,
                  playPause: button('暂停', () => pauses++),
                  nextEpisode: button('下一集', () {}),
                  progress: const SizedBox(height: 28, child: Text('进度')),
                  time: const Text('01:39 / 23:40'),
                  danmaku: button('弹幕', () {}),
                  speed: button('倍速', () {}),
                  fullscreen: button('全屏', () {}),
                  unlock: button('解锁', () {}),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final key in [
          'glass-player-title',
          'glass-player-actions',
          'glass-player-dock',
        ]) {
          expect(
            tester.getRect(find.byKey(ValueKey(key))).overlaps(pose.$1),
            isFalse,
          );
        }
        await tester.tap(find.text('选集'));
        await tester.tap(find.byTooltip('更多'));
        await tester.tap(find.byTooltip('暂停'));
      }
    }
    expect(episodes, 8);
    expect(menu, 8);
    expect(pauses, 8);
  });
}
