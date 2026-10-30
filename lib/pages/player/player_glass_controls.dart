import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/ios_scene_environment.dart';
import 'package:kazumi/pages/video/video_viewport_geometry.dart';

class PlayerGlassControlLayout {
  PlayerGlassControlLayout({
    required VideoViewportGeometry geometry,
    required bool fillsWindow,
    required double actionsWidth,
    required double topHeight,
    required double dockHeight,
    double preferredTitleWidth = 420,
  }) {
    final size = geometry.size;
    final safe = geometry.basePadding;
    final top = safe.top + (fillsWindow ? 16 : 8);
    actions = geometry.place(
      Rect.fromLTWH(
        size.width - safe.right - 16 - actionsWidth,
        top,
        actionsWidth,
        topHeight,
      ),
    );
    final titleWidth = fillsWindow
        ? math.min(
            preferredTitleWidth,
            math.min(size.width * .52, actions.left - safe.left - 28),
          )
        : 44.0;
    final proposedTitle = geometry.place(
      Rect.fromLTWH(safe.left + 16, top, math.max(44, titleWidth), topHeight),
    );
    title = Rect.fromLTRB(
      proposedTitle.left,
      top,
      math.min(proposedTitle.right, actions.left - 12),
      top + topHeight,
    );
    final available = size.width - safe.horizontal;
    final dockWidth = math.min(
      860.0,
      fillsWindow ? available * .84 : math.max(0.0, available - 24),
    );
    dock = geometry.place(
      Rect.fromLTWH(
        safe.left + (available - dockWidth) / 2,
        math.max(
          top + topHeight + 8,
          size.height - safe.bottom - (fillsWindow ? 16 : 8) - dockHeight,
        ),
        dockWidth,
        dockHeight,
      ),
    );
  }

  late final Rect title;
  late final Rect actions;
  late final Rect dock;
}

/// Controls are independent islands over a full-width video surface.
class PlayerGlassControls extends StatelessWidget {
  const PlayerGlassControls({
    super.key,
    required this.fillsWindow,
    required this.title,
    required this.back,
    required this.more,
    required this.playPause,
    required this.nextEpisode,
    required this.progress,
    required this.time,
    required this.danmaku,
    required this.speed,
    required this.fullscreen,
    required this.unlock,
    this.onEpisodes,
    this.locked = false,
  });

  final bool fillsWindow;
  final String title;
  final Widget back, more, playPause, nextEpisode, progress, time;
  final Widget danmaku, speed, fullscreen, unlock;
  final VoidCallback? onEpisodes;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final geometry = VideoViewportScope.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final topHeight = math.max(44.0, scaler.scale(14) * 1.3 + 12);
    final rowHeight = math.max(44.0, scaler.scale(12) * 1.3 + 12);
    final titleStyle = TextStyle(
      inherit: false,
      fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
      fontFamilyFallback: Theme.of(
        context,
      ).textTheme.bodyMedium?.fontFamilyFallback,
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );
    final titleMeasure = TextPainter(
      text: TextSpan(text: title, style: titleStyle),
      textDirection: Directionality.of(context),
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final preferredTitleWidth = titleMeasure.width.ceilToDouble() + 64;
    titleMeasure.dispose();
    final layout = PlayerGlassControlLayout(
      geometry: geometry,
      fillsWindow: fillsWindow,
      actionsWidth: onEpisodes == null
          ? 44
          : math.max(116, scaler.scale(14) * 2 + 76),
      topHeight: topHeight,
      dockHeight: rowHeight + 36,
      preferredTitleWidth: preferredTitleWidth,
    );
    if (locked) {
      final rect = geometry.place(
        Rect.fromLTWH(
          geometry.size.width - geometry.basePadding.right - 64,
          (geometry.size.height - 48) / 2,
          48,
          48,
        ),
      );
      return Stack(
        children: [
          Positioned.fromRect(
            rect: rect,
            child: PlayerGlassSurface(child: unlock),
          ),
        ],
      );
    }
    return IconButtonTheme(
      data: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: Colors.white,
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.all(10),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      child: Stack(
        children: [
          Positioned.fromRect(
            rect: layout.title,
            child: PlayerGlassSurface(
              key: const ValueKey('glass-player-title'),
              child: Row(
                children: [
                  back,
                  if (fillsWindow && layout.title.width > 100)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Positioned.fromRect(
            rect: layout.actions,
            child: PlayerGlassSurface(
              key: const ValueKey('glass-player-actions'),
              child: Row(
                children: [
                  if (onEpisodes != null) ...[
                    Expanded(
                      child: TextButton(
                        onPressed: onEpisodes,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          minimumSize: const Size(44, 44),
                        ),
                        child: const Text('选集', maxLines: 1),
                      ),
                    ),
                    Container(width: .5, height: 20, color: Colors.white30),
                  ],
                  more,
                ],
              ),
            ),
          ),
          Positioned.fromRect(
            rect: layout.dock,
            child: PlayerGlassSurface(
              key: const ValueKey('glass-player-dock'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: Column(
                  children: [
                    SizedBox(
                      height: 28,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: progress,
                      ),
                    ),
                    SizedBox(
                      height: rowHeight,
                      child: LayoutBuilder(
                        builder: (context, box) {
                          final readableWidth = box.maxWidth / scaler.scale(1);
                          return Row(
                            children: [
                              playPause,
                              if (readableWidth >= 400) nextEpisode,
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  child: DefaultTextStyle(
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    child: time,
                                  ),
                                ),
                              ),
                              if (readableWidth >= 340) danmaku,
                              if (readableWidth >= 460) speed,
                              fullscreen,
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PlayerGlassSurface extends StatelessWidget {
  const PlayerGlassSurface({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final opaque =
        IosSceneEnvironment.of(context).reduceTransparency ||
        MediaQuery.highContrastOf(context);
    // Keep video controls in the same compositor as video and popup menus.
    // A UIKit backdrop here can sample Flutter's later menu overlay and paint
    // over it; this clipped material samples only the video behind the dock.
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        platform: theme.platform,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: theme.colorScheme.primary,
          brightness: Brightness.dark,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: opaque ? 0 : 10,
            sigmaY: opaque ? 0 : 10,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(40),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: opaque
                    ? [const Color(0xFF242424), const Color(0xFF242424)]
                    : [
                        Colors.black.withValues(alpha: .28),
                        Colors.black.withValues(alpha: .40),
                      ],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: opaque ? .45 : .25),
                width: .7,
              ),
            ),
            child: Material(type: MaterialType.transparency, child: child),
          ),
        ),
      ),
    );
  }
}
