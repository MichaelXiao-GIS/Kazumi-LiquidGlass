import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/video/video_fullscreen_controller.dart';
import 'package:kazumi/services/platform/display_mode_service.dart';

void main() {
  testWidgets('iOS fullscreen requests landscape and releases it on every exit', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final orientations = <List<dynamic>>[];
    const landscape = [
      'DeviceOrientation.landscapeLeft',
      'DeviceOrientation.landscapeRight',
    ];
    Completer<void>? pendingRequest;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          orientations.add(List<dynamic>.from(call.arguments as List));
          await pendingRequest?.future;
        }
        return null;
      },
    );
    try {
      final fullscreen = VideoFullscreenController(
        applyFullscreen: DisplayModeService.applyVideoFullscreen,
      );
      late BuildContext routeContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              routeContext = context;
              fullscreen.attach(ModalRoute.of(context)!);
              return TextButton(
                onPressed: () => unawaited(fullscreen.toggle()),
                child: const Text('全屏'),
              );
            },
          ),
        ),
      );

      // No physical-size/rotation event is supplied: the button must request it.
      await tester.tap(find.text('全屏'));
      await tester.pumpAndSettle();
      expect(fullscreen.isFullscreen, isTrue);
      expect(orientations, [landscape]);

      await Navigator.of(routeContext).maybePop();
      await tester.pumpAndSettle();
      expect(fullscreen.isFullscreen, isFalse);
      expect(orientations.last, isEmpty);

      await fullscreen.toggle();
      await fullscreen.close();
      expect(orientations, [landscape, [], landscape, []]);

      // A rapid exit must win even when the entry request is still in flight.
      pendingRequest = Completer<void>();
      final entering = DisplayModeService.applyVideoFullscreen(true);
      final exiting = DisplayModeService.applyVideoFullscreen(false);
      await tester.pump();
      expect(orientations.last, landscape);
      expect(orientations.length, 5);
      pendingRequest.complete();
      pendingRequest = null;
      await tester.pump();
      await Future.wait([entering, exiting]);
      expect(orientations, [landscape, [], landscape, [], landscape, []]);
    } finally {
      pendingRequest?.complete();
      debugDefaultTargetPlatformOverride = null;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    }
  });
}
