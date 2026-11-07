import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/player/controller/player_danmaku_controller.dart';
import 'package:kazumi/pages/player/controller/player_playback_controller.dart';
import 'package:kazumi/pages/player/controller/player_seek_controller.dart';
import 'package:media_kit/media_kit.dart';

class _Player implements Player {
  final positions = <Duration>[];
  @override
  Future<void> seek(Duration position) async => positions.add(position);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Playback implements PlayerPlaybackController {
  @override
  Player? mediaPlayer = _Player();
  @override
  bool playerPlaying = false;
  @override
  Duration currentPosition = const Duration(seconds: 30);
  @override
  Duration duration = const Duration(minutes: 10);
  @override
  bool isCurrentPlayer(Player player) => identical(player, mediaPlayer);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Danmaku implements PlayerDanmakuController {
  @override
  void clearAndInvalidateScheduledDanmakus() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final playing in [false, true]) {
    for (final cancelled in [false, true]) {
      test('seek keeps playing=$playing when cancelled=$cancelled', () async {
        final playback = _Playback()..playerPlaying = playing;
        final player = playback.mediaPlayer! as _Player;
        var resumes = 0;
        final pause = Completer<void>();
        final seeking = PlayerSeekController(
          playback: playback,
          danmaku: _Danmaku(),
          pause: ({bool enableSync = true}) {
            playback.playerPlaying = false;
            return pause.future;
          },
          play: ({bool enableSync = true}) async {
            resumes++;
            playback.playerPlaying = true;
          },
          onSeekCompleted: (_) async {},
        );
        seeking.beginInteractiveSeek();
        seeking.updateInteractiveSeek(const Duration(minutes: 2));
        final finished = seeking.finishInteractiveSeek(cancelled: cancelled);
        expect(player.positions, isEmpty);
        pause.complete();
        expect(await finished, isTrue);
        expect(playback.playerPlaying, playing);
        expect(resumes, playing ? 1 : 0);
        expect(player.positions, cancelled ? [] : [const Duration(minutes: 2)]);
        expect(
          playback.currentPosition,
          cancelled ? const Duration(seconds: 30) : const Duration(minutes: 2),
        );
      });
    }
  }

  test(
    'changing episodes during a seek cannot resume the new player',
    () async {
      final playback = _Playback()..playerPlaying = true;
      final pause = Completer<void>();
      var resumes = 0;
      final seeking = PlayerSeekController(
        playback: playback,
        danmaku: _Danmaku(),
        pause: ({bool enableSync = true}) => pause.future,
        play: ({bool enableSync = true}) async {
          resumes++;
        },
        onSeekCompleted: (_) async {},
      );
      seeking.beginInteractiveSeek();
      seeking.updateInteractiveSeek(const Duration(minutes: 2));
      final finished = seeking.finishInteractiveSeek();
      playback.mediaPlayer = _Player();
      pause.complete();
      expect(await finished, isFalse);
      expect(resumes, 0);
      expect((playback.mediaPlayer! as _Player).positions, isEmpty);
    },
  );
}
