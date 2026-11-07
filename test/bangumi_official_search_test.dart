import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/request/clients/bangumi_client.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/request/core/network_exception.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/search_parser.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

// Exercise the real API, client, routing and decoder; replace only transport.
class _Transport implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final bodies = <dynamic>[];
  int status = 200;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final bytes = await requestStream?.expand((chunk) => chunk).toList();
    bodies.add(bytes == null ? null : jsonDecode(utf8.decode(bytes)));
    return ResponseBody.fromString(
      jsonEncode({
        'total': 1,
        'data': [
          {
            'id': 400602,
            'type': 2,
            'name': '葬送のフリーレン',
            'name_cn': '葬送的芙莉莲',
            'date': '2023-09-29',
            'images': {'large': 'https://lain.bgm.tv/pic/cover/l/test.jpg'},
            'rating': {'rank': 1, 'score': 8.0, 'total': 100},
          },
        ],
      }),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform originalPaths;
  late _Transport transport;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp(
      'kazumi_official_search_',
    );
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });
  setUp(() async {
    DioFactory.reset();
    await GStorage.resetSettings([
      SettingsKeys.bangumiAcceleration,
      SettingsKeys.enableBangumiProxy,
      SettingsKeys.bangumiSyncEnable,
      SettingsKeys.bangumiAccessToken,
    ]);
    transport = _Transport();
    DioFactory.bangumiDio.httpClientAdapter = transport;
  });
  tearDownAll(() async {
    DioFactory.reset();
    await Hive.close();
    PathProviderPlatform.instance = originalPaths;
    await directory.delete(recursive: true);
  });

  void expectOfficialSearch() {
    final request = transport.requests.last;
    expect(request.uri.host, 'api.bgm.tv');
    expect(request.uri.scheme, 'https');
    expect(request.uri.path, '/v0/search/subjects');
    expect(request.method, 'POST');
    final headers = request.headers.map(
      (key, value) => MapEntry(key.toLowerCase(), value),
    );
    expect(headers['authorization'], isNull);
    expect(headers['x-appid'], isNull);
    expect(headers['x-signature'], isNull);
    expect(headers['x-timestamp'], isNull);
    expect(
      headers['user-agent'],
      contains('MichaelXiao-GIS/Kazumi-LiquidGlass/'),
    );
    expect(headers['user-agent'], contains('(${Platform.operatingSystem})'));
  }

  for (final mode in ['mirror', 'direct', 'ech']) {
    test(
      '$mode search reaches official API and decodes results without login',
      () async {
        await GStorage.putSetting(SettingsKeys.bangumiAcceleration, mode);
        final page = await BangumiApi.bangumiSearch('葬送的芙莉莲');
        expectOfficialSearch();
        expect(transport.requests.single.extra['ech'] == true, mode == 'ech');
        expect(transport.bodies.single['keyword'], '葬送的芙莉莲');
        expect(page.rawCount, 1);
        expect(page.items.single.id, 400602);
        expect(page.items.single.nameCn, '葬送的芙莉莲');
      },
    );
  }

  test(
    'default/legacy mirror setting also searches the official API',
    () async {
      await BangumiApi.bangumiSearch('Naruto');
      expectOfficialSearch();
    },
  );

  test('official search preserves filters, sorting and pagination', () async {
    await GStorage.putSetting(SettingsKeys.bangumiAcceleration, 'mirror');
    await BangumiApi.bangumiSearch(
      '葬送',
      limit: 10,
      offset: 20,
      sort: 'score',
      tags: ['漫画改'],
      dateRange: const SearchDateRange(start: '2023-01-01', end: '2024-01-01'),
    );
    expectOfficialSearch();
    expect(transport.requests.single.uri.queryParameters, {
      'limit': '10',
      'offset': '20',
    });
    expect(
      transport.bodies.single,
      BangumiApi.buildBangumiSearchParams(
        '葬送',
        sort: 'score',
        tags: ['漫画改'],
        dateRange: const SearchDateRange(
          start: '2023-01-01',
          end: '2024-01-01',
        ),
      ),
    );
  });

  test('non-search mirror requests keep their route and signature', () async {
    await GStorage.putSetting(SettingsKeys.bangumiAcceleration, 'mirror');
    await BangumiClient.instance.get(
      '${ApiEndpoints.bangumiAPINextDomain}/p1/subjects/400602/comments',
    );
    final request = transport.requests.single;
    expect(request.uri.host, Uri.parse(ApiEndpoints.bangumiMirrorDomain).host);
    expect(request.headers['X-Signature'], isNotEmpty);
  });

  test(
    'official rejection is propagated instead of returning an empty page',
    () async {
      transport.status = 403;
      await expectLater(
        BangumiApi.bangumiSearch('葬送'),
        throwsA(
          isA<NetworkException>().having((e) => e.statusCode, 'status', 403),
        ),
      );
      expectOfficialSearch();
    },
  );
}
