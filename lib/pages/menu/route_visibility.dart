import 'package:flutter/material.dart';

/// Keeps page coverage separate from the end of an interactive transition.
class RouteVisibilityScope extends StatefulWidget {
  const RouteVisibilityScope({
    super.key,
    required this.observer,
    required this.child,
  });

  final RouteObserver<PageRoute<void>> observer;
  final Widget child;

  @override
  State<RouteVisibilityScope> createState() => _RouteVisibilityScopeState();
}

class _RouteVisibilityScopeState extends State<RouteVisibilityScope>
    with RouteAware {
  PageRoute<void>? _route;
  bool _isCovered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == _route) return;
    widget.observer.unsubscribe(this);
    _route = route is PageRoute<void> ? route : null;
    if (_route != null) widget.observer.subscribe(this, _route!);
  }

  @override
  void didUpdateWidget(covariant RouteVisibilityScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.observer != widget.observer) {
      oldWidget.observer.unsubscribe(this);
      if (_route != null) widget.observer.subscribe(this, _route!);
    }
  }

  @override
  void didPushNext() => _setCovered(true);

  @override
  void didPopNext() => _setCovered(false);

  void _setCovered(bool value) {
    if (_isCovered != value) setState(() => _isCovered = value);
  }

  @override
  void dispose() {
    widget.observer.unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      _route?.animation,
      _route?.secondaryAnimation,
      _route?.navigator?.userGestureInProgressNotifier,
    ]),
    child: widget.child,
    builder: (context, child) => RouteVisibility(
      isCovered: _isCovered,
      // didPopNext fires when a pop starts, before the page stops sliding.
      // A UIKit glass view must not re-enter that live Flutter transition.
      nativeControlsVisible:
          !_isCovered &&
          (_route?.animation?.isCompleted ?? true) &&
          (_route?.secondaryAnimation?.isDismissed ?? true) &&
          !(_route?.navigator?.userGestureInProgress ?? false),
      child: child!,
    ),
  );
}

/// Whether the surrounding route subtree is covered by another page.
///
/// Published by the page that owns the route, so long-lived children can stop
/// background work while hidden instead of inspecting the navigation stack.
class RouteVisibility extends InheritedWidget {
  const RouteVisibility({
    super.key,
    required this.isCovered,
    this.nativeControlsVisible = true,
    required super.child,
  });

  final bool isCovered;
  final bool nativeControlsVisible;

  static bool nativeControlsVisibleOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<RouteVisibility>()
          ?.nativeControlsVisible ??
      true;

  /// Subscribes; dependents are notified only when the state flips.
  static bool isCoveredOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<RouteVisibility>()
            ?.isCovered ??
        false;
  }

  @override
  bool updateShouldNotify(RouteVisibility oldWidget) =>
      isCovered != oldWidget.isCovered ||
      nativeControlsVisible != oldWidget.nativeControlsVisible;
}
