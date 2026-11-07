import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/search/search_history_module.dart';
import 'package:kazumi/pages/search/search_controller.dart';
import 'package:kazumi/pages/search/search_page.dart';
import 'package:kazumi/repositories/collect_repository.dart';
import 'package:kazumi/repositories/search_history_repository.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/request/core/network_exception.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/search_parser.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _Collect implements ICollectRepository {
  @override
  bool getPrivateMode() => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _History implements ISearchHistoryRepository {
  @override
  List<SearchHistory> getAllHistories() => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Search extends SearchPageController {
  _Search() : super(_Collect(), _History());
  final requests = <Completer<BangumiSearchPage>>[];
  final offsets = <int>[];
  @override
  Future<BangumiSearchPage> fetchSearchPage(
    SearchFilterState filters,
    int offset,
  ) {
    offsets.add(offset);
    final request = Completer<BangumiSearchPage>();
    requests.add(request);
    return request.future;
  }
}

const denied = NetworkException(
  type: NetworkExceptionType.badResponse,
  message: 'unauthorized',
  statusCode: 401,
);
const empty = BangumiSearchPage(items: [], rawCount: 0);
BangumiItem item() => BangumiItem(
  id: 1,
  type: 2,
  name: '测试番剧',
  nameCn: '测试番剧',
  summary: '',
  airDate: '',
  airWeekday: 1,
  rank: 0,
  images: {},
  tags: [],
  alias: [],
  ratingScore: 0,
  votes: 0,
  votesCount: [],
  info: '',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform originalPaths;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('kazumi_search_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = originalPaths;
    await directory.delete(recursive: true);
  });
  testWidgets(
    '401 shows recoverable error, retry can return real empty result',
    (tester) async {
      final search = _Search();
      await tester.pumpWidget(
        MaterialApp(
          home: SearchPage(controller: search, initialQuery: 'frieren'),
        ),
      );
      await tester.pump();
      search.requests.single.completeError(denied);
      await tester.pumpAndSettle();
      expect(find.text('搜索未完成'), findsOneWidget);
      expect(find.textContaining('搜索服务拒绝了请求'), findsOneWidget);
      expect(find.text('没有找到番剧'), findsNothing);
      expect(find.text('0 部番剧'), findsNothing);
      expect(find.text('网络设置'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pump();
      expect(search.offsets, [0, 0]);
      search.requests.last.complete(empty);
      await tester.pumpAndSettle();
      expect(find.text('没有找到番剧'), findsOneWidget);
      expect(find.text('搜索未完成'), findsNothing);
      expect(search.isTimeOut, isFalse);
      expect(search.hasMoreSearchResults, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'failed pagination retains results and retries the same offset',
    () async {
      final search = _Search();
      var pending = search.searchBangumi('frieren', type: 'init');
      search.requests.last.complete(
        BangumiSearchPage(items: [item()], rawCount: 20),
      );
      await pending;
      pending = search.searchBangumi('frieren');
      search.requests.last.completeError(denied);
      await pending;
      expect(search.bangumiList.single.id, 1);
      expect(search.isLoading, isFalse);
      expect(search.isTimeOut, isTrue);
      pending = search.searchBangumi('frieren');
      search.requests.last.complete(empty);
      await pending;
      expect(search.offsets, [0, 20, 20]);
      expect(search.searchError, isEmpty);
    },
  );
  test('old failed request cannot replace a newer successful search', () async {
    final search = _Search();
    final old = search.searchBangumi('old', type: 'init');
    final fresh = search.searchBangumi('new', type: 'init');
    search.requests.last.complete(
      BangumiSearchPage(items: [item()], rawCount: 1),
    );
    await fresh;
    search.requests.first.completeError(denied);
    await old;
    expect(search.bangumiList.single.id, 1);
    expect(search.isTimeOut, isFalse);
    expect(search.searchError, isEmpty);
  });
  test('transport errors leave search retryable', () async {
    final search = _Search();
    final pending = search.searchBangumi('frieren', type: 'init');
    search.requests.last.completeError(const SocketException('offline'));
    await pending;
    expect(search.searchError, '搜索请求失败，请检查网络后重试');
    expect(search.hasMoreSearchResults, isTrue);
    expect(search.isLoading, isFalse);
  });
}
