import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/utils/adaptive_layout.dart';
import 'package:kazumi/bean/widget/ios_scene_environment.dart';
import 'package:kazumi/services/platform/display_mode_service.dart';

/// Place above Scaffold to measure the window without keyboard insets.
class VideoSystemBars extends StatefulWidget {
  const VideoSystemBars({
    super.key,
    required this.fullscreen,
    required this.isPip,
    required this.child,
  });

  final bool fullscreen;
  final bool isPip;
  final Widget child;

  @override
  State<VideoSystemBars> createState() => _VideoSystemBarsState();
}

class _VideoSystemBarsState extends State<VideoSystemBars> with RouteAware {
  PageRoute<void>? _route;
  bool _visible = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<void> && !identical(route, _route)) {
      rootRouteObserver.unsubscribe(this);
      _route = route;
      _visible = route.isCurrent;
      rootRouteObserver.subscribe(this, route);
    }
    _sync();
  }

  @override
  void didUpdateWidget(covariant VideoSystemBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didPushNext() => _setVisible(false);

  @override
  void didPopNext() => _setVisible(true);

  @override
  void didPop() => _setVisible(false);

  void _setVisible(bool visible) {
    _visible = visible;
    _sync();
  }

  void _sync() {
    if (!_visible || _route?.isActive == false) {
      unawaited(DisplayModeService.releaseSystemBars(this));
    } else if (!widget.isPip) {
      // PiP keeps the full-window preference until its original metrics return.
      final size = MediaQuery.sizeOf(context);
      final scene = IosSceneEnvironment.of(context);
      final divided =
          scene.matches(size) &&
          (AdaptiveLayout.horizontalDivision(size, scene.divisions) != null ||
              AdaptiveLayout.verticalDivision(size, scene.divisions) != null);
      final fillsWindow =
          !divided &&
          AdaptiveLayout.playerFillsWindow(
            size,
            fullscreen: false,
            isPip: false,
          );
      unawaited(
        DisplayModeService.setSystemBarsHidden(
          owner: this,
          hidden: widget.fullscreen || fillsWindow,
        ),
      );
    }
  }

  @override
  void dispose() {
    rootRouteObserver.unsubscribe(this);
    unawaited(DisplayModeService.releaseSystemBars(this));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
