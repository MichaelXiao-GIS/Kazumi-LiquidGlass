import 'package:kazumi/modules/danmaku/danmaku_ch_convert.dart';
import 'package:kazumi/modules/danmaku/danmaku_episode_response.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/modules/danmaku/danmaku_search_response.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/request/apis/platform_danmaku_api.dart';
import 'package:kazumi/request/clients/danmaku_client.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/dandan_credentials.dart';
import 'package:lpinyin/lpinyin.dart';

class DanmakuApi {
  static final _client = DanmakuClient.instance;

  static Set<DanmakuSource> get enabledSources => {
    if (GStorage.getSetting(SettingsKeys.danmakuGamerSource))
      DanmakuSource.gamer,
    if (GStorage.getSetting(SettingsKeys.danmakuBiliBiliSource))
      DanmakuSource.bilibili,
    if (GStorage.getSetting(SettingsKeys.danmakuDanDanSource))
      DanmakuSource.dandan,
  };

  static Future<DanmakuEpisodeResponse> _dandanEpisodes(String path) async {
    final json = await _client.get(ApiEndpoints.dandanAPIDomain + path);
    return DanmakuEpisodeResponse.fromJson(json);
  }

  static final _traditionalCharacters = <String, String>{
    for (final e in ChineseHelper.chineseMap.entries.toList().reversed)
      e.value: e.key,
  };

  static Future<List<DanmakuEntry>> comments(DanmakuEpisode episode) async {
    if (episode.source != DanmakuSource.dandan) {
      final entries = await PlatformDanmakuApi.comments(episode);
      final conversion = DanmakuChConvert.fromValue(
        GStorage.getSetting(SettingsKeys.danmakuChConvert),
      );
      if (conversion != DanmakuChConvert.none) {
        for (final entry in entries) {
          entry.message = conversion == DanmakuChConvert.simplified
              ? ChineseHelper.convertToSimplifiedChinese(entry.message)
              : entry.message
                    .split('')
                    .map((c) => _traditionalCharacters[c] ?? c)
                    .join();
        }
      }
      return entries;
    }
    final json = await _client.get(
      '${ApiEndpoints.dandanAPIDomain}${ApiEndpoints.dandanAPIComment}${episode.episodeId}',
      queryParameters: {
        'withRelated': 'true',
        'chConvert': DanmakuChConvert.fromValue(
          GStorage.getSetting(SettingsKeys.danmakuChConvert),
        ).value.toString(),
      },
    );
    if (json['success'] == false || (json['errorCode'] ?? 0) != 0) {
      throw StateError('弹弹play：${json['errorMessage'] ?? json['errorCode']}');
    }
    return [
      for (final comment in (json['comments'] as List? ?? const []))
        DanmakuEntry.fromJson(comment),
    ];
  }

  static DanmakuEpisode? matchEpisode(
    List<DanmakuEpisode> episodes,
    int number,
  ) => episodes.where((entry) => entry.number == number).singleOrNull;

  // One unavailable broadcaster must never discard another broadcaster's result.
  static Future<List<T>> _collect<T>(
    List<Future<List<T>> Function()> loaders,
  ) async {
    Object? error;
    final results = await Future.wait(
      loaders.map((load) async {
        try {
          return await load();
        } catch (e) {
          error = e;
          KazumiLogger().w('Danmaku source unavailable', error: e);
          return <T>[];
        }
      }),
    );
    final combined = results.expand((rows) => rows).toList();
    if (combined.isEmpty && error != null) throw error!;
    return combined;
  }

  static Future<({List<DanmakuEntry> entries, int dandanId})> load(
    int subject,
    int episode, {
    String airDate = '',
  }) async {
    final sources = enabledSources;
    var dandanId = 0;
    Future<Map<String, dynamic>?>? mapping;
    final directSources = <DanmakuSource>{};
    List<DanmakuEntry> signed = [];
    final loaded = await _collect<DanmakuEntry>([
      for (final source in sources.where((s) => s != DanmakuSource.dandan))
        () async {
          final series = await (mapping ??= PlatformDanmakuApi.series(
            subject,
            airDate,
          ));
          final episodes = await PlatformDanmakuApi.episodes(
            series,
            source,
            requestedNumber: episode,
          );
          final match = matchEpisode(episodes, episode);
          if (match == null) return [];
          final entries = await comments(match);
          if (entries.isNotEmpty) directSources.add(source);
          return entries;
        },
      if (sources.contains(DanmakuSource.dandan) && hasDandanCredentials)
        () async {
          final series = await _dandanEpisodes(
            ApiEndpoints.formatUrl(ApiEndpoints.dandanAPIInfoByBgmBangumiId, [
              subject,
            ]),
          );
          dandanId = series.bangumiId;
          final match = matchEpisode(series.episodes, episode);
          if (match == null) return [];
          signed = await comments(match);
          return signed;
        },
      if (!hasDandanCredentials &&
          sources.length == 1 &&
          sources.contains(DanmakuSource.dandan))
        () async => throw StateError('此版本未配置弹弹play授权'),
    ]);
    // The signed API can supply the same broadcaster with a different timestamp
    // or translation. Pick one feed per broadcaster; viewer deduplication is optional.
    final signedEntries = signed.toSet();
    loaded.removeWhere((entry) {
      if (!signedEntries.contains(entry)) return false;
      final source = entry.source.contains('Gamer')
          ? DanmakuSource.gamer
          : entry.source.contains('BiliBili')
          ? DanmakuSource.bilibili
          : DanmakuSource.dandan;
      return !sources.contains(source) || directSources.contains(source);
    });
    return (entries: loaded, dandanId: dandanId);
  }

  static Future<DanmakuSearchResponse> searchAnimes(String title) async {
    final sources = enabledSources;
    var hasMore = false;
    final animes = await _collect<DanmakuSearchAnime>([
      if (sources.any((s) => s != DanmakuSource.dandan))
        () async {
          final result = await BangumiApi.bangumiSearch(title);
          hasMore |= result.rawCount >= 20;
          return [
            for (final item in result.items)
              DanmakuSearchAnime(
                animeId: item.id,
                animeTitle: item.nameCn,
                airDate: item.airDate,
                isBangumiSubject: true,
                typeDescription: '站点弹幕 · ${item.airDate}',
              ),
          ];
        },
      if (hasDandanCredentials && sources.contains(DanmakuSource.dandan))
        () async {
          final json = await _client.get(
            ApiEndpoints.dandanAPIDomain + ApiEndpoints.dandanAPISearchEpisodes,
            queryParameters: {'anime': title, 'v2': 'true'},
          );
          final result = DanmakuSearchResponse.fromJson(json);
          hasMore |= result.hasMore;
          return result.animes;
        },
      if (!hasDandanCredentials &&
          sources.length == 1 &&
          sources.contains(DanmakuSource.dandan))
        () async => throw StateError('此版本未配置弹弹play授权'),
    ]);
    return DanmakuSearchResponse(animes: animes, hasMore: hasMore);
  }

  static Future<List<DanmakuEpisode>> episodes(DanmakuSearchAnime anime) async {
    if (!anime.isBangumiSubject) {
      return (await _dandanEpisodes(
        '${ApiEndpoints.dandanAPIInfo}${anime.animeId}',
      )).episodes;
    }
    final series = await PlatformDanmakuApi.series(
      anime.animeId,
      anime.airDate,
    );
    final episodes = await _collect<DanmakuEpisode>([
      for (final source in enabledSources.where(
        (s) => s != DanmakuSource.dandan,
      ))
        () => PlatformDanmakuApi.episodes(series, source),
    ]);
    episodes.sort((a, b) {
      final number = a.number!.compareTo(b.number!);
      return number != 0 ? number : a.source.index.compareTo(b.source.index);
    });
    return episodes;
  }
}
