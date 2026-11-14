import 'package:flutter/widgets.dart';

class NavigationScrollToTopController extends ChangeNotifier {
  void scrollToTop() => notifyListeners();
}

/// Lets the active page handle another tap on the recommendation tab.
class NavigationScrollToTop extends InheritedWidget {
  const NavigationScrollToTop({
    super.key,
    required this.controller,
    required this.inNavigation,
    required super.child,
  });

  final NavigationScrollToTopController controller;
  final bool inNavigation;

  static NavigationScrollToTop? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NavigationScrollToTop>();

  @override
  bool updateShouldNotify(NavigationScrollToTop oldWidget) =>
      controller != oldWidget.controller ||
      inNavigation != oldWidget.inNavigation;
}
