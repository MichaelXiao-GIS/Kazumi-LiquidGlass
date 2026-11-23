import 'package:dio/dio.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/request/core/ech_adapter.dart';
import 'package:kazumi/request/core/network_error_mapper.dart';
import 'package:kazumi/services/network/bangumi_acceleration.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/bangumi_mirror_credentials.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/utils/crypto.dart';

class BangumiClient {
  BangumiClient._();

  static final BangumiClient instance = BangumiClient._();

  Future<dynamic> get(
    String url, {
    Map<String, dynamic>? queryParameters,
    bool requiresAuth = false,
    String? accessToken,
    CancelToken? cancelToken,
  }) => _request(
    'GET',
    url,
    queryParameters: queryParameters,
    requiresAuth: requiresAuth,
    accessToken: accessToken,
    cancelToken: cancelToken,
  );

  Future<dynamic> post(
    String url, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool requiresAuth = false,
    CancelToken? cancelToken,
  }) => _request(
    'POST',
    url,
    data: data,
    queryParameters: queryParameters,
    requiresAuth: requiresAuth,
    cancelToken: cancelToken,
  );

  Future<dynamic> _request(
    String method,
    String url, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    required bool requiresAuth,
    String? accessToken,
    CancelToken? cancelToken,
  }) async {
    final uri = Uri.parse(url);
    final mirrorComment = ApiEndpoints.isMirrorCommentRequest(uri, method);
    final route = _route(uri, method, requiresAuth, mirrorComment);
    try {
      final response = await DioFactory.bangumiDio.request(
        route == BangumiAcceleration.mirror
            ? ApiEndpoints.bangumiMirrorDomain +
                  uri.path +
                  (uri.hasQuery ? '?${uri.query}' : '')
            : url,
        data: data,
        queryParameters: queryParameters,
        options: Options(
          method: method,
          headers: _headers(
            officialDestination:
                route != BangumiAcceleration.mirror &&
                uri.scheme == 'https' &&
                ApiEndpoints.bangumiPublicApiHosts.contains(uri.host),
            signComment: route == BangumiAcceleration.mirror && mirrorComment,
            requiresAuth: requiresAuth,
            accessToken: accessToken,
            method: method,
            path: uri.path,
          ),
          extra: route == BangumiAcceleration.ech ? echExtra : null,
        ),
        cancelToken: cancelToken,
      );
      return response.data;
    } on DioException catch (e) {
      throw await NetworkErrorMapper.mapException(e);
    }
  }

  /// User-scoped requests always reach the official API over ECH.
  BangumiAcceleration _route(
    Uri uri,
    String method,
    bool requiresAuth,
    bool mirrorComment,
  ) {
    if (!ApiEndpoints.bangumiPublicApiHosts.contains(uri.host)) {
      return BangumiAcceleration.direct;
    }
    if (requiresAuth) return BangumiAcceleration.ech;
    final mode = BangumiAcceleration.current;
    if (mode == BangumiAcceleration.mirror) {
      final search = method == 'POST' && uri.path == '/v0/search/subjects';
      final unsignedComment =
          mirrorComment &&
          (bangumiMirrorCredentials['id']!.isEmpty ||
              bangumiMirrorCredentials['value']!.isEmpty);
      if (search || unsignedComment) return BangumiAcceleration.direct;
    }
    return mode;
  }

  Map<String, dynamic> _headers({
    required bool officialDestination,
    required bool signComment,
    required bool requiresAuth,
    String? accessToken,
    required String method,
    required String path,
  }) {
    final headers = <String, dynamic>{...bangumiHTTPHeader};
    final bangumiSyncEnable = GStorage.getSetting(
      SettingsKeys.bangumiSyncEnable,
    );
    final token =
        (accessToken ??
                GStorage.getSetting<String>(SettingsKeys.bangumiAccessToken))
            .trim();
    if (officialDestination &&
        (requiresAuth || bangumiSyncEnable) &&
        token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (signComment) {
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      headers['X-AppId'] = bangumiMirrorCredentials['id'];
      headers['X-Timestamp'] = timestamp;
      headers['X-Signature'] = generateBangumiMirrorSearchSignature(
        method: method,
        path: path,
        body: '',
        timestamp: timestamp,
      );
    }
    return headers;
  }
}
