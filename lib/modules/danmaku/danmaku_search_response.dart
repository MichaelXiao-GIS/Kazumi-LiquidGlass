/// Response of `/api/v2/search/episodes`.
///
/// Entries carry no cover, rating or air date, unlike `/api/v2/search/anime`.
class DanmakuSearchAnime {
  final int animeId;
  final bool isBangumiSubject;
  final String airDate;
  final String animeTitle;
  final String typeDescription;

  const DanmakuSearchAnime({
    required this.animeId,
    this.isBangumiSubject = false,
    this.airDate = '',
    required this.animeTitle,
    required this.typeDescription,
  });

  factory DanmakuSearchAnime.fromJson(Map<String, dynamic> json) {
    return DanmakuSearchAnime(
      animeId: json['animeId'],
      animeTitle: json['animeTitle'],
      typeDescription: json['typeDescription'] ?? '',
    );
  }
}

class DanmakuSearchResponse {
  final List<DanmakuSearchAnime> animes;

  /// Result set was truncated; the user should narrow the keyword.
  final bool hasMore;

  const DanmakuSearchResponse({required this.animes, required this.hasMore});

  factory DanmakuSearchResponse.fromJson(Map<String, dynamic> json) {
    if (json['success'] == false || (json['errorCode'] ?? 0) != 0) {
      throw StateError('弹弹play：${json['errorMessage'] ?? json['errorCode']}');
    }
    final list = json['animes'] as List? ?? const [];
    return DanmakuSearchResponse(
      animes: list.map((i) => DanmakuSearchAnime.fromJson(i)).toList(),
      hasMore: json['hasMore'] ?? false,
    );
  }
}
