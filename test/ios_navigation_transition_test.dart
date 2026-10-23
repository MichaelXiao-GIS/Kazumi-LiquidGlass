import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/ios_glass.dart';
import 'package:kazumi/pages/menu/adaptive_navigation_scaffold.dart';
import 'package:kazumi/pages/menu/route_visibility.dart';
import 'package:kazumi/utils/theme.dart';

const _contentKey = ValueKey('retained content');

Future<GlobalKey<NavigatorState>> _mountShell(WidgetTester tester) async {
  final navigator = GlobalKey<NavigatorState>();
  final observer = RouteObserver<PageRoute<void>>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      navigatorObservers: [observer],
      theme: iosAppTheme(ThemeData()),
      // The real shell uses a PageRouteBuilder; the covering pages use the
      // material route with Cupertino transitions from iosAppTheme.
      onGenerateRoute: (_) => PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => RouteVisibilityScope(
          observer: observer,
          child: AdaptiveNavigationScaffold(
            selectedIndex: 3,
            onSelected: (_) {},
            onSearch: () {},
            child: Scaffold(
              body: ListView(
                key: _contentKey,
                children: const [SizedBox(height: 3000, child: Text('我的'))],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return navigator;
}

MaterialPageRoute<void> _details(String title) => MaterialPageRoute<void>(
  builder: (_) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: const SizedBox.expand(),
  ),
);

void main() {
  for (final size in [const Size(390, 844), const Size(900, 650)]) {
    testWidgets('glass stays absent until a back animation ends at $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final navigator = await _mountShell(tester);
      final contentElement = tester.element(find.byKey(_contentKey));
      await tester.drag(find.byKey(_contentKey), const Offset(0, -250));
      await tester.pumpAndSettle();
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
      final offset = scroll.position.pixels;
      expect(find.byType(IosGlassNavigation), findsOneWidget);

      navigator.currentState!.push<void>(_details('设置'));
      await tester.pump();
      expect(
        find.byType(IosGlassNavigation, skipOffstage: false),
        findsNothing,
      );
      await tester.pumpAndSettle();
      navigator.currentState!.push<void>(_details('播放设置'));
      await tester.pumpAndSettle();
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(
        find.byType(IosGlassNavigation, skipOffstage: false),
        findsNothing,
      );

      navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byType(IosGlassNavigation, skipOffstage: false),
        findsNothing,
      );
      await tester.pumpAndSettle();
      expect(find.byType(IosGlassNavigation), findsOneWidget);
      expect(tester.element(find.byKey(_contentKey)), same(contentElement));
      expect(scroll.position.pixels, offset);
      expect(
        tester
            .widget<IosGlassNavigation>(find.byType(IosGlassNavigation))
            .selectedIndex,
        3,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'cancelled and completed back swipes keep glass hidden at $size',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final navigator = await _mountShell(tester);
        navigator.currentState!.push<void>(_details('设置'));
        await tester.pumpAndSettle();
        final drag = await tester.startGesture(Offset(1, size.height / 2));
        await drag.moveBy(Offset(size.width * .2, 0));
        await tester.pump();
        expect(navigator.currentState!.userGestureInProgress, isTrue);
        expect(
          find.byType(IosGlassNavigation, skipOffstage: false),
          findsNothing,
        );
        await tester.pump(const Duration(milliseconds: 500));
        await drag.up();
        await tester.pumpAndSettle();
        expect(navigator.currentState!.canPop(), isTrue);
        expect(
          find.byType(IosGlassNavigation, skipOffstage: false),
          findsNothing,
        );

        final back = await tester.startGesture(Offset(1, size.height / 2));
        await back.moveBy(Offset(size.width * .7, 0));
        await tester.pump();
        expect(
          find.byType(IosGlassNavigation, skipOffstage: false),
          findsNothing,
        );
        await tester.pump(const Duration(milliseconds: 500));
        await back.up();
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          find.byType(IosGlassNavigation, skipOffstage: false),
          findsNothing,
        );
        await tester.pumpAndSettle();
        expect(navigator.currentState!.canPop(), isFalse);
        expect(find.byType(IosGlassNavigation), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('dialogs do not unmount the page navigation', (tester) async {
    final navigator = await _mountShell(tester);
    final navigationState = tester.state(find.byType(IosGlassNavigation));
    showCupertinoDialog<void>(
      context: navigator.currentContext!,
      builder: (_) => const CupertinoAlertDialog(title: Text('测试对话框')),
    );
    await tester.pumpAndSettle();
    expect(
      tester.state(find.byType(IosGlassNavigation)),
      same(navigationState),
    );
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(
      tester.state(find.byType(IosGlassNavigation)),
      same(navigationState),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('native glass is hidden before deferred platform disposal', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final messenger = tester.binding.defaultBinaryMessenger;
    final channels = <MethodChannel>[];
    final events = <String>[];
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map)['id'];
        final channel = MethodChannel('com.predidit.kazumi/glass/$id');
        channels.add(channel);
        messenger.setMockMethodCallHandler(channel, (call) async {
          events.add(call.method);
          return null;
        });
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
      for (final channel in channels) {
        messenger.setMockMethodCallHandler(channel, null);
      }
    });
    final navigator = await _mountShell(tester);
    expect(find.byType(UiKitView), findsOneWidget);
    expect(channels, hasLength(1));
    navigator.currentState!.push<void>(_details('设置'));
    await tester.pump();
    expect(find.byType(UiKitView, skipOffstage: false), findsNothing);
    expect(events, contains('hide'));
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(channels, hasLength(1));
    await tester.pumpAndSettle();
    expect(channels, hasLength(2));
    expect(find.byType(UiKitView), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
