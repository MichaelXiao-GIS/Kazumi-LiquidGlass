import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:kazumi/modules/danmaku/danmaku_episode_response.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/utils/danmaku.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:xml/xml.dart';

/// bangumi-data links a Bangumi subject to each broadcaster's series ID.
/// Episode IDs are always obtained from the corresponding broadcaster.
class PlatformDanmakuApi {
  static const _gamer = 'https://api.gamer.com.tw/anime/v1';
  static const _bili = 'https://api.bilibili.com';
  static const _catalog =
      'https://raw.githubusercontent.com/bangumi-data/bangumi-data/master/data/items';
  static final _months = <String, (DateTime, List<dynamic>)>{};

  static Future<dynamic> _json(
    String url, [
    Map<String, dynamic>? query,
  ]) async {
    final response = await DioFactory.apiDio.get(
      url,
      queryParameters: query,
      options: Options(
        responseType: ResponseType.json,
        headers: Uri.parse(url).host == 'api.bgm.tv' ? bangumiHTTPHeader : null,
      ),
    );
    final body = response.data;
    final data = body is String ? jsonDecode(body) : body;
    if (data is Map && (data['error'] != null || (data['code'] ?? 0) != 0)) {
      throw FormatException('弹幕接口返回错误：${data['code'] ?? data['error']}');
    }
    return data;
  }

  static Future<List<dynamic>> _month(String month) async {
    try {
      return await _json('$_catalog/$month.json') as List;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) rethrow;
      return await _json(
            'https://cdn.jsdelivr.net/gh/bangumi-data/bangumi-data@master/data/items/$month.json',
          )
          as List;
    }
  }

  static Future<Map<String, dynamic>?> series(
    int subject,
    String airDate,
  ) async {
    if (airDate.isEmpty) {
      final data = await _json('https://api.bgm.tv/v0/subjects/$subject');
      airDate = data['date'] ?? '';
    }
    final date = DateTime.tryParse(airDate);
    if (date == null) return null;
    // Some catalogs use the local broadcast date across a month boundary.
    final months = {
      for (final day in [
        date,
        date.subtract(const Duration(days: 1)),
        date.add(const Duration(days: 1)),
      ])
        '${day.year}/${day.month.toString().padLeft(2, '0')}',
    };
    for (final month in months) {
      var cached = _months[month];
      if (cached == null || DateTime.now().difference(cached.$1).inHours >= 1) {
        try {
          final rows = await _month(month);
          if (_months.length >= 12) _months.remove(_months.keys.first);
          cached = _months[month] = (DateTime.now(), rows);
        } on DioException catch (e) {
          if (e.response?.statusCode == 404) continue;
          rethrow;
        }
      }
      for (final row in cached.$2.whereType<Map<String, dynamic>>()) {
        if ((row['sites'] as List).any(
          (site) =>
              site['site'] == 'bangumi' && site['id'].toString() == '$subject',
        )) {
          return row;
        }
      }
    }
    return null;
  }

  static Future<List<DanmakuEpisode>> episodes(
    Map<String, dynamic>? series,
    DanmakuSource source, {
    int? requestedNumber,
  }) async {
    if (series == null) return [];
    final sites = {
      for (final site in series['sites'] as List)
        site['site']: site['id'].toString(),
    };
    if (source == DanmakuSource.gamer) {
      final acg = sites['gamer'] ?? sites['gamer_hk'];
      if (acg == null) return [];
      for (final keyword in <String>{
        ...?series['titleTranslate']?['zh-Hant']?.cast<String>(),
        series['title'] as String,
      }) {
        final search = await _json('$_gamer/search.php', {'kw': keyword});
        final animes = search['data']['animeList'] as List;
        final hit = animes
            .where((a) => a['acgSn'].toString() == acg)
            .firstOrNull;
        if (hit == null) continue;
        final video = await _json('$_gamer/video.php', {
          'videoSn': hit['videoSn'],
        });
        final anime = video['data']['anime'];
        if (anime['acgSn'].toString() != acg) continue;
        return _numbered(
          anime['episodes']['0'] ?? [],
          source,
          'episode',
          'videoSn',
        );
      }
      return [];
    }
    final episodes = <DanmakuEpisode>[];
    Object? error;
    for (final media in {
      sites['bilibili'],
      sites['bilibili_hk_mo_tw'],
      sites['bilibili_hk_mo'],
      sites['bilibili_tw'],
    }.nonNulls) {
      try {
        final review = await _json('$_bili/pgc/review/user', {
          'media_id': media,
        });
        final season = review['result']['media']['season_id'];
        final data = await _json('$_bili/pgc/view/web/season', {
          'season_id': season,
        });
        final edition = _numbered(
          data['result']['episodes'],
          source,
          'title',
          'cid',
        );
        final existing = episodes.map((e) => e.number).toSet();
        episodes.addAll(edition.where((e) => !existing.contains(e.number)));
        if (requestedNumber != null &&
            episodes.any((e) => e.number == requestedNumber)) {
          break;
        }
      } catch (e) {
        error = e;
      }
    }
    if (error != null &&
        (episodes.isEmpty ||
            (requestedNumber != null &&
                !episodes.any((e) => e.number == requestedNumber)))) {
      throw error;
    }
    return episodes;
  }

  static List<DanmakuEpisode> _numbered(
    List rows,
    DanmakuSource source,
    String labelKey,
    String idKey,
  ) {
    final episodes = <DanmakuEpisode>[];
    for (final row in rows) {
      final number = DanmakuEpisode.regularEpisodeNumber(row[labelKey]);
      final id = int.tryParse(row[idKey].toString());
      if (number == null || id == null || id <= 0) continue;
      episodes.add(
        DanmakuEpisode(
          episodeId: id,
          number: number,
          source: source,
          episodeTitle:
              '第 $number 集 · ${source == DanmakuSource.gamer ? 'Gamer' : 'BiliBili'}',
        ),
      );
    }
    return episodes;
  }

  static Future<List<DanmakuEntry>> comments(DanmakuEpisode episode) async {
    if (episode.source == DanmakuSource.gamer) {
      final data = await _json('$_gamer/danmu.php', {
        'videoSn': episode.episodeId,
        'geo': 'TW,HK',
      });
      return parseGamer(data['data']['danmu'] as List);
    }
    final response = await DioFactory.apiDio.get<List<int>>(
      '$_bili/x/v1/dm/list.so',
      queryParameters: {'oid': episode.episodeId},
      options: Options(responseType: ResponseType.bytes),
    );
    return parseBilibili(response.data!);
  }

  static List<DanmakuEntry> parseGamer(List rows) {
    final entries = <DanmakuEntry>[];
    for (final row in rows.whereType<Map>()) {
      final time = double.tryParse('${row['time']}');
      final message = row['text'];
      if (message is! String ||
          message.isEmpty ||
          time == null ||
          !time.isFinite ||
          time < 0) {
        continue;
      }
      final type = switch ('${row['position']}') {
        '0' => 1,
        '1' => 5,
        '2' => 4,
        _ => null,
      };
      if (type == null) continue;
      final rgb = int.tryParse(
        '${row['color']}'.replaceFirst('#', ''),
        radix: 16,
      );
      entries.add(
        DanmakuEntry(
          message: message,
          time: time / 10,
          type: type,
          color: generateDanmakuColor(rgb ?? 0xffffff),
          source: '[Gamer]',
        ),
      );
    }
    return entries;
  }

  static List<DanmakuEntry> parseBilibili(List<int> bytes) {
    if (bytes.isEmpty) throw const FormatException('BiliBili 弹幕响应为空');
    final first = bytes.skipWhile((b) => b <= 32).firstOrNull;
    if (first != 60 && first != 0xef) {
      if (bytes.first == 0x1f) {
        bytes = gzip.decode(bytes);
      } else {
        try {
          bytes = zlib.decode(bytes);
        } on FormatException {
          bytes = ZLibDecoder(raw: true).convert(bytes);
        }
      }
    }
    final root = XmlDocument.parse(utf8.decode(bytes)).rootElement;
    if (root.name.local != 'i') throw const FormatException('BiliBili 弹幕格式错误');
    final entries = <DanmakuEntry>[];
    for (final row in root.findElements('d')) {
      final p = row.getAttribute('p')?.split(',');
      if (p == null || p.length < 4) continue;
      final time = double.tryParse(p[0]);
      final mode = int.tryParse(p[1]);
      if (time == null ||
          !time.isFinite ||
          time < 0 ||
          mode == null ||
          mode < 1 ||
          mode > 5 ||
          row.innerText.isEmpty) {
        continue;
      }
      entries.add(
        DanmakuEntry(
          message: row.innerText,
          time: time,
          type: mode < 4 ? 1 : mode,
          color: generateDanmakuColor(int.tryParse(p[3]) ?? 0xffffff),
          source: '[BiliBili]',
        ),
      );
    }
    return entries;
  }
}
