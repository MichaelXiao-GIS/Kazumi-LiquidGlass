import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/widget/ios_scene_environment.dart';

bool get _nativeIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// Native UIGlassEffect on iOS 26+, system material on earlier iOS versions.
/// Only navigation/controls use glass; content retains an opaque surface.
class IosGlassSurface extends StatelessWidget {
  const IosGlassSurface({super.key, this.radius = 24, this.child});
  final double radius;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final opaque =
        IosSceneEnvironment.of(context).reduceTransparency ||
        MediaQuery.highContrastOf(context);
    final surface = Theme.of(context).colorScheme.surface;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: _nativeIOS
                  ? UiKitView(
                      viewType: 'com.predidit.kazumi/glass',
                      key: ValueKey(dark),
                      creationParamsCodec: const StandardMessageCodec(),
                      creationParams: {
                        'kind': 'surface',
                        'radius': radius,
                        'dark': dark,
                      },
                    )
                  : BackdropFilter(
                      filter: ui.ImageFilter.blur(
                        sigmaX: opaque ? 0 : 20,
                        sigmaY: opaque ? 0 : 20,
                      ),
                      child: ColoredBox(
                        color: surface.withValues(alpha: opaque ? 1 : .88),
                      ),
                    ),
            ),
          ),
          ?child,
        ],
      ),
    );
  }
}

const iosNavigationLabels = ['推荐', '时间表', '追番', '我的'];
const iosNavigationIcons = [
  CupertinoIcons.play_rectangle,
  CupertinoIcons.calendar,
  CupertinoIcons.heart,
  CupertinoIcons.person_crop_circle,
];

class IosGlassNavigation extends StatefulWidget {
  const IosGlassNavigation({
    super.key,
    required this.vertical,
    required this.selectedIndex,
    required this.onSelected,
    required this.onSearch,
  });
  final bool vertical;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onSearch;

  @override
  State<IosGlassNavigation> createState() => _IosGlassNavigationState();
}

class _IosGlassNavigationState extends State<IosGlassNavigation> {
  MethodChannel? _channel;
  Map<String, Object> get _configuration => {
    'kind': 'navigation',
    'vertical': widget.vertical,
    'selectedIndex': widget.selectedIndex,
    'dark': Theme.of(context).brightness == Brightness.dark,
    'tint': Theme.of(context).colorScheme.primary.toARGB32(),
  };

  void _update() => _channel?.invokeMethod<void>('update', _configuration);

  @override
  void didUpdateWidget(covariant IosGlassNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_nativeIOS) {
      return UiKitView(
        viewType: 'com.predidit.kazumi/glass',
        creationParamsCodec: const StandardMessageCodec(),
        creationParams: _configuration,
        onPlatformViewCreated: (id) {
          if (!mounted) return;
          _channel = MethodChannel('com.predidit.kazumi/glass/$id');
          _channel!.setMethodCallHandler((call) async {
            if (!mounted) return;
            if (call.method == 'select' && call.arguments is int) {
              final index = call.arguments as int;
              if (index >= 0 && index < iosNavigationLabels.length) {
                widget.onSelected(index);
              }
            } else if (call.method == 'search') {
              widget.onSearch();
            }
          });
          _update();
        },
      );
    }
    final children = <Widget>[
      for (var index = 0; index < iosNavigationLabels.length; index++)
        Expanded(
          child: Semantics(
            selected: index == widget.selectedIndex,
            child: TextButton(
              onPressed: () => widget.onSelected(index),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.all(4),
                foregroundColor: index == widget.selectedIndex
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(iosNavigationIcons[index], size: 23),
                  const SizedBox(height: 3),
                  Text(
                    iosNavigationLabels[index],
                    maxLines: 1,
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
      IconButton(
        tooltip: '搜索',
        onPressed: widget.onSearch,
        icon: const Icon(CupertinoIcons.search),
      ),
    ];
    return IosGlassSurface(
      radius: 32,
      child: widget.vertical
          ? Column(children: children)
          : Row(children: children),
    );
  }
}
