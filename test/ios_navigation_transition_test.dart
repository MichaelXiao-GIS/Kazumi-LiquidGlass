import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/menu/ios_system_tabs.dart';
import 'package:kazumi/pages/menu/adaptive_navigation_scaffold.dart';
import 'package:kazumi/pages/menu/route_visibility.dart';
import 'package:kazumi/utils/theme.dart';

const _contentKey = ValueKey('retained content');

Future<GlobalKey<NavigatorState>> _mountShell(
  WidgetTester tester, {
  ValueChanged<int>? onSelected,
  VoidCallback? onSearch,
}) async {
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
            onSelected: onSelected ?? (_) {},
            onSearch: onSearch ?? () {},
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
      expect(find.byType(IosSystemTabs), findsOneWidget);

      navigator.currentState!.push<void>(_details('设置'));
      await tester.pump();
      expect(find.byType(IosSystemTabs, skipOffstage: false), findsNothing);
      await tester.pumpAndSettle();
      navigator.currentState!.push<void>(_details('播放设置'));
      await tester.pumpAndSettle();
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byType(IosSystemTabs, skipOffstage: false), findsNothing);

      navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(IosSystemTabs, skipOffstage: false), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byType(IosSystemTabs), findsOneWidget);
      expect(tester.element(find.byKey(_contentKey)), same(contentElement));
      expect(scroll.position.pixels, offset);
      expect(
        tester.widget<IosSystemTabs>(find.byType(IosSystemTabs)).selectedIndex,
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
        expect(find.byType(IosSystemTabs, skipOffstage: false), findsNothing);
        await tester.pump(const Duration(milliseconds: 500));
        await drag.up();
        await tester.pumpAndSettle();
        expect(navigator.currentState!.canPop(), isTrue);
        expect(find.byType(IosSystemTabs, skipOffstage: false), findsNothing);

        final back = await tester.startGesture(Offset(1, size.height / 2));
        await back.moveBy(Offset(size.width * .7, 0));
        await tester.pump();
        expect(find.byType(IosSystemTabs, skipOffstage: false), findsNothing);
        await tester.pump(const Duration(milliseconds: 500));
        await back.up();
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byType(IosSystemTabs, skipOffstage: false), findsNothing);
        await tester.pumpAndSettle();
        expect(navigator.currentState!.canPop(), isFalse);
        expect(find.byType(IosSystemTabs), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'system tab events select only destinations and dispatch search separately',
    (tester) async {
      final selected = <int>[];
      var searches = 0;
      await _mountShell(
        tester,
        onSelected: selected.add,
        onSearch: () => searches++,
      );
      final messenger = tester.binding.defaultBinaryMessenger;
      const channel = MethodChannel('com.predidit.kazumi/tabs');
      for (final index in [0, 1, 2, 3, 4, -1]) {
        await messenger.handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(MethodCall('select', index)),
          null,
        );
      }
      await messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(const MethodCall('search')),
        null,
      );
      expect(selected, [0, 1, 2, 3]);
      expect(searches, 1);
    },
  );

  testWidgets('modal dialogs take priority over native navigation', (
    tester,
  ) async {
    final navigator = await _mountShell(tester);
    showCupertinoDialog<void>(
      context: navigator.currentContext!,
      builder: (_) => const CupertinoAlertDialog(title: Text('测试对话框')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(IosSystemTabs, skipOffstage: false), findsNothing);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(IosSystemTabs), findsOneWidget);
  });

  testWidgets('updates and hides the native controller with the route', (
    tester,
  ) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    const channel = MethodChannel('com.predidit.kazumi/tabs');
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final navigator = await _mountShell(tester);
    expect(calls.last.method, 'update');
    expect(calls.last.arguments['selectedIndex'], 3);
    expect(calls.last.arguments['visible'], true);
    navigator.currentState!.push<void>(_details('设置'));
    await tester.pump();
    expect(calls.last.method, 'hide');
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls.last.method, 'hide');
    await tester.pumpAndSettle();
    expect(calls.last.method, 'update');
    expect(calls.last.arguments['selectedIndex'], 3);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(calls.last.method, 'hide');
  });
}
