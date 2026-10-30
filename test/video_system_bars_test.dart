import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/video/video_system_bars.dart';

void main() {
  testWidgets('iOS inline playback hides status area and restores it on exit', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final modes = <dynamic>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
          modes.add(call.arguments);
        }
        return null;
      },
    );
    try {
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [rootRouteObserver],
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const VideoSystemBars(
                      fullscreen: false,
                      isPip: false,
                      child: Scaffold(body: Text('播放页')),
                    ),
                  ),
                );
              },
              child: const Text('播放'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('播放'));
      await tester.pumpAndSettle();
      expect(modes.last, 'SystemUiMode.immersiveSticky');
      final context = tester.element(find.text('播放页'));
      Navigator.of(context).pop();
      await tester.pumpAndSettle();
      expect(modes.last, 'SystemUiMode.edgeToEdge');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    }
  });
}
