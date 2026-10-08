/// Media type classification for universal content support.
///
/// Rules are not required to specify a [type]. When absent the engine
/// defaults to [MediaType.unknown] and the item is still fully playable.
enum MediaType {
  movie,
  tv,
  anime,
  variety,
  documentary,
  sports,
  mv,
  video,
  other,
  unknown;

  /// Parse from a string, returning [unknown] for null or unrecognised input.
  static MediaType fromString(String? value) {
    if (value == null || value.isEmpty) return MediaType.unknown;
    return MediaType.values.firstWhere(
      (e) => e.name == value.toLowerCase(),
      orElse: () => MediaType.unknown,
    );
  }

  /// Human-readable label (Chinese).
  String get label => switch (this) {
        MediaType.movie => '电影',
        MediaType.tv => '电视剧',
        MediaType.anime => '动漫',
        MediaType.variety => '综艺',
        MediaType.documentary => '纪录片',
        MediaType.sports => '体育',
        MediaType.mv => 'MV',
        MediaType.video => '视频',
        MediaType.other => '其他',
        MediaType.unknown => '未知',
      };
}
