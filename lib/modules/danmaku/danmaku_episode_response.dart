enum DanmakuSource { dandan, gamer, bilibili }

class DanmakuEpisode {
  final int episodeId;
  final int? number;
  final DanmakuSource source;
  final String episodeTitle;

  DanmakuEpisode({
    required this.episodeId,
    required this.episodeTitle,
    this.number,
    this.source = DanmakuSource.dandan,
  });

  factory DanmakuEpisode.fromJson(Map<String, dynamic> json) {
    return DanmakuEpisode(
      episodeId: json['episodeId'],
      episodeTitle: json['episodeTitle'] ?? '${json['episodeNumber'] ?? ''}',
      number: regularEpisodeNumber(
        json['episodeNumber'] ?? json['episodeTitle'],
      ),
    );
  }

  static int? regularEpisodeNumber(dynamic label) {
    final match = RegExp(
      r'^(?:第\s*)?(\d+)(?:\.0+)?(?:\s*[话話集])?$',
    ).firstMatch(label?.toString().trim() ?? '');
    return match == null ? null : int.tryParse(match[1]!);
  }

  Map<String, dynamic> toJson() {
    return {
      'episodeId': episodeId,
      'episodeTitle': episodeTitle,
      'episodeNumber': number?.toString(),
    };
  }
}

class DanmakuEpisodeResponse {
  int bangumiId;
  List<DanmakuEpisode> episodes;
  int errorCode;
  bool success;
  String errorMessage;

  DanmakuEpisodeResponse({
    required this.bangumiId,
    required this.episodes,
    required this.errorCode,
    required this.success,
    required this.errorMessage,
  });

  factory DanmakuEpisodeResponse.fromJson(Map<String, dynamic> json) {
    if (json['success'] == false || (json['errorCode'] ?? 0) != 0) {
      throw StateError('弹弹play：${json['errorMessage'] ?? json['errorCode']}');
    }
    final list = json['bangumi']?['episodes'] as List? ?? const [];
    List<DanmakuEpisode> episodeList = list
        .map((i) => DanmakuEpisode.fromJson(i))
        .toList();

    return DanmakuEpisodeResponse(
      bangumiId: json['bangumi']?['animeId'] ?? 0,
      episodes: episodeList,
      errorCode: json['errorCode'] ?? 0,
      success: json['success'] ?? true,
      errorMessage: json['errorMessage'] ?? '',
    );
  }

  factory DanmakuEpisodeResponse.fromTemplate() {
    return DanmakuEpisodeResponse(
      bangumiId: 0,
      episodes: [],
      errorCode: 0,
      success: false,
      errorMessage: '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bangumi': {
        'animeId': bangumiId,
        'episodes': episodes.map((episode) => episode.toJson()).toList(),
      },
      'errorCode': errorCode,
      'success': success,
      'errorMessage': errorMessage,
    };
  }
}
