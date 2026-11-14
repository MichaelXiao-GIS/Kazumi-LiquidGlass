import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/menu/adaptive_navigation_scaffold.dart';

void main() {
  testWidgets(
    'only vertical reading drags compact the native tabs and reverse reading restores them',
    (tester) async {
      final compact = <bool>[];
      const channel = MethodChannel('com.predidit.kazumi/tabs');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'update') {
          compact.add(call.arguments['compact'] as bool);
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final scroll = ScrollController();
      final index = ValueNotifier(0);
      final height = ValueNotifier(4000.0);
      addTearDown(scroll.dispose);
      addTearDown(index.dispose);
      addTearDown(height.dispose);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: ValueListenableBuilder<int>(
            valueListenable: index,
            builder: (_, tab, _) => AdaptiveNavigationScaffold(
              selectedIndex: tab,
              onSelected: (value) => index.value = value,
              onSearch: () {},
              child: Column(
                children: [
                  SizedBox(
                    height: 100,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: const [SizedBox(width: 4000)],
                    ),
                  ),
                  Expanded(
                    child: ValueListenableBuilder<double>(
                      valueListenable: height,
                      builder: (_, value, _) => ListView(
                        key: const ValueKey('vertical'),
                        controller: scroll,
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        children: [SizedBox(height: value)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final vertical = find.byKey(const ValueKey('vertical'));
      Future<void> drag(Offset offset) async {
        await tester.drag(vertical, offset);
        await tester.pumpAndSettle();
      }

      Future<void> send(String method, [int? value]) async {
        await messenger.handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(MethodCall(method, value)),
          null,
        );
        await tester.pumpAndSettle();
      }

      expect(compact, [false]);
      await tester.dragFrom(const Offset(200, 50), const Offset(-160, 0));
      await tester.pumpAndSettle();
      await drag(const Offset(0, 160)); // Top bounce.
      await drag(const Offset(0, -24)); // Smaller than the reading threshold.
      expect(compact, [false]);
      await drag(const Offset(0, -180));
      expect(compact, [false, true]);
      await drag(const Offset(0, 75));
      expect(compact.last, false);
      await drag(const Offset(0, -120));
      await send('select', 0);
      expect(compact.last, false);
      await drag(const Offset(0, -120));
      await send('select', 2);
      expect(compact.last, false);
      await drag(const Offset(0, -120));
      expect(compact.last, true);
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const Scaffold()),
      );
      await tester.pumpAndSettle();
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(compact.last, false);
      await drag(const Offset(0, -120));
      expect(compact.last, true);
      tester.view.physicalSize = const Size(844, 390);
      await tester.pumpAndSettle();
      expect(compact.last, false);
      await drag(const Offset(0, -120));
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(compact.last, false);
      await drag(const Offset(0, -120));
      expect(compact.last, true);
      height.value = 100;
      await tester.pumpAndSettle();
      expect(compact.last, false);
      await drag(const Offset(0, -120)); // Short list bounces at the bottom.
      expect(compact.last, false);
    },
  );
}
