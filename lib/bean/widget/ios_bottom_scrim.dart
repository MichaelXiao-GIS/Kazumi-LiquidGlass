import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/ios_scene_environment.dart';

/// A non-interactive fade over content scrolling behind the home area.
class IosBottomScrim extends StatelessWidget {
  const IosBottomScrim({super.key});

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final opaque =
        IosSceneEnvironment.of(context).reduceTransparency ||
        MediaQuery.highContrastOf(context);
    return IgnorePointer(
      child: ExcludeSemantics(
        child: ClipRect(
          child: opaque
              ? ColoredBox(color: surface)
              : BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: CustomPaint(
                    painter: _BottomTint(surface),
                    child: const SizedBox.expand(),
                  ),
                ),
        ),
      ),
    );
  }
}

class _BottomTint extends CustomPainter {
  const _BottomTint(this.surface);
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(bounds, Paint()..color = surface.withValues(alpha: .55));
    // Mask inside the backdrop layer. An ancestor ShaderMask would isolate the
    // backdrop in an empty saveLayer and leave only a tint, without any blur.
    canvas.drawRect(
      bounds,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.white, Colors.white],
          stops: [0, .4, 1],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(_BottomTint oldDelegate) => surface != oldDelegate.surface;
}
