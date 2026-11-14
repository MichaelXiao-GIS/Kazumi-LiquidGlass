import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Connects the visible Flutter menu route to the scene's UITabBarController.
class IosSystemTabs extends StatefulWidget {
  const IosSystemTabs({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.onSearch,
    required this.onScrollToTop,
    required this.onScrollToTopPlacement,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onSearch;
  final VoidCallback? onScrollToTop;
  final ValueChanged<bool> onScrollToTopPlacement;

  @override
  State<IosSystemTabs> createState() => _IosSystemTabsState();
}

class _IosSystemTabsState extends State<IosSystemTabs> {
  static const _channel = OptionalMethodChannel('com.predidit.kazumi/tabs');
  static _IosSystemTabsState? _owner;
  Map<String, Object>? _lastUpdate;

  @override
  void initState() {
    super.initState();
    _owner = this;
    _channel.setMethodCallHandler((call) async {
      if (!mounted || !(ModalRoute.isCurrentOf(context) ?? true)) return;
      final index = call.arguments;
      if (call.method == 'select' && index is int && index >= 0 && index < 4) {
        widget.onSelected(index);
      } else if (call.method == 'search') {
        widget.onSearch();
      } else if (call.method == 'scrollToTop') {
        widget.onScrollToTop?.call();
      } else if (call.method == 'scrollToTopPlacement' &&
          call.arguments is bool) {
        widget.onScrollToTopPlacement(call.arguments as bool);
      }
    });
  }

  @override
  void dispose() {
    if (_owner == this) {
      _owner = null;
      _channel.setMethodCallHandler(null);
      _channel.invokeMethod<void>('hide');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final configuration = {
      'visible': true,
      'selectedIndex': widget.selectedIndex,
      'scrollToTop': widget.onScrollToTop != null,
      'dark': theme.brightness == Brightness.dark,
      'tint': theme.colorScheme.primary.toARGB32(),
    };
    if (!mapEquals(_lastUpdate, configuration)) {
      _lastUpdate = configuration;
      _channel.invokeMethod<void>('update', configuration);
    }
    return const SizedBox.shrink();
  }
}
