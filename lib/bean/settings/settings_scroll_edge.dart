import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/ios_bottom_scrim.dart';

/// Keep the viewport full height; reserve the home area in scroll content only.
EdgeInsets settingsScrollPadding(BuildContext context, EdgeInsets padding) =>
    padding.copyWith(
      bottom:
          padding.bottom +
          (Theme.of(context).platform == TargetPlatform.iOS
              ? MediaQuery.paddingOf(context).bottom
              : 0),
    );

class SettingsScrollEdge extends StatelessWidget {
  const SettingsScrollEdge({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final show =
        enabled &&
        Theme.of(context).platform == TargetPlatform.iOS &&
        media.padding.bottom > 0 &&
        media.viewInsets.bottom == 0;
    // Keep the body in the same tree position when the keyboard opens.
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (show)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: math.min(
                constraints.maxHeight,
                media.padding.bottom + 16,
              ),
              child: const IosBottomScrim(),
            ),
        ],
      ),
    );
  }
}
