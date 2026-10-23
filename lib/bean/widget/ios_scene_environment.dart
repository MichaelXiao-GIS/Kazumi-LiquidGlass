import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

@immutable
class IosSceneData {
  const IosSceneData({
    this.size = Size.zero,
    this.occlusions = const [],
    this.divisions = const [],
    this.reduceTransparency = false,
    this.reduceMotion = false,
    this.highContrast = false,
  });

  factory IosSceneData.fromMap(Map<Object?, Object?> map) {
    List<Rect> regions(String key) => [
      for (final value in (map[key] as List? ?? const []))
        if (value is List && value.length == 4)
          Rect.fromLTWH(
            (value[0] as num).toDouble(),
            (value[1] as num).toDouble(),
            (value[2] as num).toDouble(),
            (value[3] as num).toDouble(),
          ),
    ];
    return IosSceneData(
      size: Size(
        (map['width'] as num? ?? 0).toDouble(),
        (map['height'] as num? ?? 0).toDouble(),
      ),
      occlusions: regions('occlusions'),
      divisions: regions('divisions'),
      reduceTransparency: map['reduceTransparency'] == true,
      reduceMotion: map['reduceMotion'] == true,
      highContrast: map['highContrast'] == true,
    );
  }

  final Size size;
  final List<Rect> occlusions;
  final List<Rect> divisions;
  final bool reduceTransparency;
  final bool reduceMotion;
  final bool highContrast;

  /// Ignore the previous pose's coordinates while Flutter catches up on resize.
  bool matches(Size viewport) =>
      (size.width - viewport.width).abs() < 1 &&
      (size.height - viewport.height).abs() < 1;
}

class IosSceneEnvironment extends StatefulWidget {
  const IosSceneEnvironment({super.key, required this.child});
  final Widget child;

  static IosSceneData of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SceneScope>()?.data ??
      const IosSceneData();

  @override
  State<IosSceneEnvironment> createState() => _IosSceneEnvironmentState();
}

class _IosSceneEnvironmentState extends State<IosSceneEnvironment> {
  StreamSubscription<dynamic>? _subscription;
  IosSceneData _data = const IosSceneData();

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      _subscription = const EventChannel('com.predidit.kazumi/scene')
          .receiveBroadcastStream()
          .listen(
            (event) {
              if (mounted && event is Map) {
                setState(() => _data = IosSceneData.fromMap(event));
              }
            },
            onError: (Object error) {
              // Flutter's safe areas remain the baseline on older engine/OS versions.
              debugPrint('iOS scene metrics unavailable: $error');
            },
          );
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return _SceneScope(
      data: _data,
      child: MediaQuery(
        data: media.copyWith(
          disableAnimations: media.disableAnimations || _data.reduceMotion,
          highContrast: media.highContrast || _data.highContrast,
          // Flutter's dialog/sheet routes already understand display features.
          // Publish native division regions so those routes also avoid the fold.
          displayFeatures: [
            ...media.displayFeatures,
            if (_data.matches(media.size))
              for (final rect in _data.divisions)
                if (!media.displayFeatures.any(
                  (feature) => feature.bounds == rect,
                ))
                  ui.DisplayFeature(
                    bounds: rect,
                    type: ui.DisplayFeatureType.fold,
                    state: ui.DisplayFeatureState.postureHalfOpened,
                  ),
          ],
        ),
        child: widget.child,
      ),
    );
  }
}

class _SceneScope extends InheritedWidget {
  const _SceneScope({required this.data, required super.child});
  final IosSceneData data;
  @override
  bool updateShouldNotify(_SceneScope oldWidget) => data != oldWidget.data;
}
