import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/danmaku/danmaku_episode_response.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/player/controller/player_danmaku_controller.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/request/apis/danmaku_api.dart';
import 'package:kazumi/request/apis/platform_danmaku_api.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/dandan_credentials.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

const _council = 554779;
const _frieren = 400602;
const _airDate = '2026-10-03';
const _gamerIds = {5: 52088, 6: 52627};
const _cid = 1339446971;
const _xml =
    '<i><d p="9.125,5,25,65280,0,0">A &amp; B</d>'
    '<d p="NaN,1,25,255">bad timestamp</d><d p="5,7,25,1">script</d></i>';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _Downloads extends Fake implements DownloadController {
  List<DanmakuEntry>? cache;

  @override
  Future<List<DanmakuEntry>?> getCachedDanmakus(
    int bangumiId,
    String pluginName,
    int episodeNumber,
  ) async => cache;

  @override
  Future<void> updateCachedDanmakus(
    int bangumiId,
    String pluginName,
    int episodeNumber,
    List<DanmakuEntry> danmakus,
    int danDanBangumiID,
  ) async {
    cache = danmakus.map((e) => DanmakuEntry.fromJson(e.toJson())).toList();
  }
}

// Only the HTTP transport is replaced. Real catalog routing, decoders, filters,
// settings and episode selection run for both signed and unsigned test builds.
class _Transport implements HttpClientAdapter {
  final requests = <Uri>[];
  String? gamerMessage;
  bool failBili = false;
  bool failGamer = false;
  bool failDandan = false;

  ResponseBody json(Object data, {String type = 'application/json'}) =>
      ResponseBody.fromString(
        jsonEncode(data),
        200,
        headers: {
          Headers.contentTypeHeader: [type],
        },
      );

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    final uri = options.uri;
    requests.add(uri);
    final q = uri.queryParameters;
    if (uri.host == 'raw.githubusercontent.com') {
      return json([
        {
          'title': '生徒会にも穴はある！',
          'titleTranslate': {
            'zh-Hant': ['學生會也有洞！'],
          },
          'sites': [
            {'site': 'bangumi', 'id': '$_council'},
            {'site': 'gamer', 'id': '144986'},
          ],
        },
        {
          'title': '葬送のフリーレン',
          'titleTranslate': {
            'zh-Hant': ['葬送的芙莉蓮'],
          },
          'sites': [
            {'site': 'bangumi', 'id': '$_frieren'},
            {'site': 'bilibili', 'id': '21087073'},
            {'site': 'gamer', 'id': '12345'},
          ],
        },
      ], type: 'text/plain; charset=utf-8');
    }
    if (uri.host == 'api.dandanplay.net' && failDandan) {
      return ResponseBody.fromString('denied', 403);
    }
    if (uri.host == 'api.bilibili.com' && failBili ||
        uri.host == 'api.gamer.com.tw' && failGamer) {
      return ResponseBody.fromString('unavailable', 503);
    }
    switch (uri.path) {
      case '/v0/search/subjects':
        return json({
          'data': [
            {
              'id': _council,
              'type': 2,
              'name': '生徒会にも穴はある！',
              'name_cn': '学生会也有洞！',
              'date': _airDate,
              'images': {'large': ''},
              'rating': {'rank': 0, 'score': 0, 'total': 0},
            },
          ],
        });
      case '/v0/subjects/$_council':
        return json({'date': _airDate});
      case '/anime/v1/search.php':
        return json({
          'data': {
            'animeList': [
              {'acgSn': 96543, 'videoSn': 100},
              {'acgSn': 144986, 'videoSn': 51813},
              {'acgSn': 12345, 'videoSn': 123},
            ],
          },
        });
      case '/anime/v1/video.php':
        final council = q['videoSn'] == '51813';
        if (!council && q['videoSn'] != '123') break;
        return json({
          'data': {
            'anime': {
              'acgSn': council ? 144986 : 12345,
              'episodes': {
                '0': [
                  if (council)
                    for (final ep in _gamerIds.entries)
                      {'episode': ep.key, 'videoSn': ep.value}
                  else
                    {'episode': 1, 'videoSn': 1001},
                ],
                '1': [
                  {'episode': 5, 'videoSn': 999},
                ],
              },
            },
          },
        });
      case '/anime/v1/danmu.php':
        return json({
          'data': {
            'danmu': [
              {
                'time': 95,
                'position': 2,
                'color': '#00FF00',
                'text': gamerMessage ?? 'gamer-${q['videoSn']}',
              },
            ],
          },
        });
      case '/pgc/review/user':
        if (q['media_id'] == '21087073') {
          return json({
            'code': 0,
            'result': {
              'media': {'season_id': 46089},
            },
          });
        }
        break;
      case '/pgc/view/web/season':
        if (q['season_id'] == '46089') {
          return json({
            'code': 0,
            'result': {
              'episodes': [
                {'title': 'PV', 'cid': 10},
                {'title': '1', 'id': 779775, 'cid': _cid},
              ],
            },
          });
        }
        break;
      case '/x/v1/dm/list.so':
        if (q['oid'] == '$_cid') {
          return ResponseBody.fromBytes(
            ZLibEncoder(raw: true).convert(utf8.encode(_xml)),
            200,
          );
        }
        break;
      case '/api/v2/bangumi/bgmtv/$_council':
        return json({
          'success': true,
          'errorCode': 0,
          'bangumi': {
            'animeId': 27182,
            'episodes': [
              {
                'episodeId': 1234,
                'episodeNumber': 'SP5',
                'episodeTitle': '特别篇',
              },
              {
                'episodeId': 91623478,
                'episodeNumber': '05',
                'episodeTitle': '正片',
              },
            ],
          },
        });
      case '/api/v2/comment/91623478':
        return json({
          'success': true,
          'errorCode': 0,
          'comments': [
            {'p': '1,1,255,[DanDanPlay]', 'm': 'signed'},
            {'p': '9.6,4,65280,[Gamer]', 'm': 'signed-gamer'},
          ],
        });
    }
    throw StateError('Unexpected request $uri');
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory state;
  late PathProviderPlatform original;
  late _Transport transport;
  setUpAll(() async {
    state = await Directory.systemTemp.createTemp('kazumi_danmaku_');
    original = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(state.path);
    Hive.init(state.path);
    await GStorage.init();
  });
  setUp(() async {
    DioFactory.reset();
    transport = _Transport();
    // Direct-source tests also run with dummy credentials and rejected signatures.
    transport.failDandan = true;
    DioFactory.apiDio.httpClientAdapter = transport;
    DioFactory.bangumiDio.httpClientAdapter = transport;
    await GStorage.resetSettings([
      SettingsKeys.danmakuBiliBiliSource,
      SettingsKeys.danmakuGamerSource,
      SettingsKeys.danmakuDanDanSource,
      SettingsKeys.danmakuChConvert,
    ]);
  });
  tearDownAll(() async {
    DioFactory.reset();
    await Hive.close();
    PathProviderPlatform.instance = original;
    await state.delete(recursive: true);
  });

  test('giriGiriLove 05 and 06 resolve the distinct Gamer video IDs', () async {
    for (final entry in _gamerIds.entries) {
      final selection = EpisodeRef.online(
        listIndex: 1,
        roadIndex: 0,
        displayTitle: '0${entry.key}',
        pageUrl: '/watch',
      );
      final result = await DanmakuApi.load(
        _council,
        selection.danmakuEpisodeNumber,
        airDate: _airDate,
      );
      final comment = result.entries.single;
      expect(comment.message, 'gamer-${entry.value}');
      expect(comment.time, 9.5);
      expect(comment.type, 4);
      expect(comment.color.toARGB32(), 0xff00ff00);
      expect(comment.source, contains('Gamer'));
    }
    expect(
      transport.requests.any((u) => u.host == 'api.bilibili.com'),
      isFalse,
    );
  });

  test(
    'BiliBili raw deflate survives Gamer and signed service failures',
    () async {
      transport.failGamer = true;
      final result = await DanmakuApi.load(_frieren, 1, airDate: '2023-09-29');
      final comment = result.entries.single;
      expect(comment.message, 'A & B');
      expect(comment.time, 9.125);
      expect(comment.type, 5);
      expect(comment.color.toARGB32(), 0xff00ff00);
      expect(comment.source, contains('BiliBili'));
      expect(
        transport.requests.any((u) => u.queryParameters['oid'] == '$_cid'),
        isTrue,
      );
    },
  );

  test('Gamer survives BiliBili and signed service failures', () async {
    transport.failBili = true;
    final result = await DanmakuApi.load(_frieren, 1, airDate: '2023-09-29');
    expect(result.entries.single.message, 'gamer-1001');
  });

  test('disabled Gamer does not fetch or return Gamer comments', () async {
    await GStorage.putSetting(SettingsKeys.danmakuGamerSource, false);
    await GStorage.putSetting(SettingsKeys.danmakuDanDanSource, false);
    final result = await DanmakuApi.load(_frieren, 1, airDate: '2023-09-29');
    expect(result.entries.single.source, contains('BiliBili'));
    expect(
      transport.requests.any((u) => u.host == 'api.dandanplay.net'),
      isFalse,
    );
    expect(
      transport.requests.any((u) => u.host == 'api.gamer.com.tw'),
      isFalse,
    );
  });

  test(
    'direct comments honor simplified and traditional display settings',
    () async {
      final episode = DanmakuEpisode(
        episodeId: 52088,
        episodeTitle: '第 5 集',
        source: DanmakuSource.gamer,
      );
      for (final (setting, original, expected) in [
        (1, '學生會', '学生会'),
        (2, '学生会', '學生會'),
      ]) {
        transport.gamerMessage = original;
        await GStorage.putSetting(SettingsKeys.danmakuChConvert, setting);
        expect((await DanmakuApi.comments(episode)).single.message, expected);
      }
    },
  );

  test(
    'manual search, episode selection and comments keep the Gamer identity',
    () async {
      final search = await DanmakuApi.searchAnimes('学生会也有洞');
      final anime = search.animes.single;
      expect(anime.animeId, _council);
      final episodes = await DanmakuApi.episodes(anime);
      final sixth = episodes.singleWhere((entry) => entry.number == 6);
      expect(sixth.source, DanmakuSource.gamer);
      expect(sixth.episodeId, 52627);
      expect((await DanmakuApi.comments(sixth)).single.message, 'gamer-52627');
    },
  );

  test(
    'local playback fetches a missing cache and reopens it offline',
    () async {
      final downloads = _Downloads();
      final player = PlayerDanmakuController(
        isLocalPlayback: () => true,
        downloadController: downloads,
      );
      final initial = await player.fetchDanmaku(_council, 'giriGiriLove', 5);
      expect(initial.hasDanmakus, isTrue);
      final requests = transport.requests.length;
      final offline = await player.fetchDanmaku(_council, 'giriGiriLove', 5);
      expect(
        offline.danmakus.single.toJson(),
        initial.danmakus.single.toJson(),
      );
      expect(transport.requests.length, requests);
    },
  );

  test(
    'no broadcaster mapping is empty; an unreachable provider is a failure',
    () async {
      await GStorage.putSetting(SettingsKeys.danmakuDanDanSource, false);
      await GStorage.putSetting(SettingsKeys.danmakuGamerSource, false);
      final result = await DanmakuApi.load(_council, 5, airDate: _airDate);
      expect(result.entries, isEmpty);
      transport.failBili = true;
      await expectLater(
        DanmakuApi.load(_frieren, 1, airDate: '2023-09-29'),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'HTTP status',
            503,
          ),
        ),
      );
    },
  );

  test('uncompressed, zlib and gzip XML keep text, skip invalid rows', () {
    final xml = utf8.encode(_xml);
    for (final bytes in [xml, zlib.encode(xml), gzip.encode(xml)]) {
      expect(PlatformDanmakuApi.parseBilibili(bytes).single.message, 'A & B');
    }
    expect(PlatformDanmakuApi.parseBilibili(utf8.encode('<i/>')), isEmpty);
    expect(
      () => PlatformDanmakuApi.parseBilibili(utf8.encode('<html/>')),
      throwsFormatException,
    );
  });

  test(
    'signed episode matching excludes specials, fractions and ambiguous numbers',
    () {
      DanmakuEpisode parse(String number) => DanmakuEpisode.fromJson({
        'episodeId': 19,
        'episodeNumber': number,
        'episodeTitle': 'subtitle',
      });
      final specials = [parse('SP1'), parse('1.5')];
      expect(DanmakuApi.matchEpisode(specials, 1), isNull);
      final regular = parse('01');
      expect(DanmakuApi.matchEpisode([...specials, regular], 1), same(regular));
      expect(DanmakuApi.matchEpisode([regular, parse('第 1 話')], 1), isNull);
    },
  );

  test(
    'DanDanPlay uses the returned episode ID or reports unavailable authorization',
    () async {
      await GStorage.putSetting(SettingsKeys.danmakuBiliBiliSource, false);
      await GStorage.putSetting(SettingsKeys.danmakuGamerSource, false);
      transport.failDandan = false;
      if (hasDandanCredentials) {
        final result = await DanmakuApi.load(_council, 5);
        expect(result.entries.single.message, 'signed');
        expect(result.dandanId, 27182);
        expect(transport.requests.last.path, '/api/v2/comment/91623478');
        await GStorage.putSetting(SettingsKeys.danmakuGamerSource, true);
        final both = await DanmakuApi.load(_council, 5, airDate: _airDate);
        expect(
          both.entries.map((entry) => entry.message),
          unorderedEquals(['signed', 'gamer-52088']),
        );
        transport.failGamer = true;
        final fallback = await DanmakuApi.load(_council, 5, airDate: _airDate);
        expect(
          fallback.entries.map((entry) => entry.message),
          unorderedEquals(['signed', 'signed-gamer']),
        );
      } else {
        await expectLater(DanmakuApi.load(_council, 5), throwsStateError);
        expect(transport.requests, isEmpty);
      }
    },
  );
}
