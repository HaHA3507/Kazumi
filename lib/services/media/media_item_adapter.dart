import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/bangumi_tag.dart';
import 'package:kazumi/modules/media/media_item.dart';
import 'package:kazumi/modules/media/media_type.dart';

/// Adapts [BangumiItem] to [MediaItem] and vice versa.
///
/// This allows the new universal media layer to work with existing
/// Bangumi-sourced data without modifying the [BangumiItem] class or
/// its Hive adapter.
///
/// Conversions are lossy in the direction [MediaItem] → [BangumiItem]:
/// the adapter populates the core fields and stores extra metadata in
/// the [MediaItem.metadata] map.
class MediaItemAdapter {
  MediaItemAdapter._();

  /// Convert a [BangumiItem] to a [MediaItem].
  ///
  /// The [sourceId] defaults to "bangumi" for items from the Bangumi API.
  /// Callers may override it (e.g. to "bangumi:pluginName" when the item
  /// was discovered through a plugin search).
  static MediaItem fromBangumiItem(
    BangumiItem item, {
    String sourceId = 'bangumi',
    String? detailUrl,
  }) {
    final cover = item.images['large'] ??
        item.images['common'] ??
        item.images['medium'] ??
        item.images['small'];

    final mediaType = _bangumiTypeToMediaType(item.type);

    return MediaItem(
      id: '$sourceId:${item.id}',
      title: item.nameCn.isNotEmpty ? item.nameCn : item.name,
      originalTitle: item.nameCn.isNotEmpty && item.name != item.nameCn
          ? item.name
          : null,
      cover: cover != null && cover.isNotEmpty ? cover : null,
      description: item.summary.isNotEmpty ? item.summary : null,
      year: _extractYear(item.airDate),
      genre: mediaType.label,
      detailUrl: detailUrl,
      sourceId: sourceId,
      type: mediaType,
      metadata: _buildMetadata(item),
    );
  }

  /// Convert a [MediaItem] back to a [BangumiItem].
  ///
  /// This is a lossy conversion: extra metadata stored in [MediaItem.metadata]
  /// is used to reconstruct Bangumi fields where possible.
  /// Returns null when the [MediaItem.id] does not contain a parseable
  /// Bangumi subject ID.
  static BangumiItem? toBangumiItem(MediaItem item) {
    final bangumiId = _extractBangumiId(item.id);
    if (bangumiId == null) return null;

    return BangumiItem(
      id: bangumiId,
      type: _mediaTypeToBangumiType(item.type),
      name: item.originalTitle ?? item.title,
      nameCn: item.title,
      summary: item.description ?? '',
      airDate: item.metadata?['airDate'] as String? ?? item.year ?? '',
      airWeekday: item.metadata?['airWeekday'] as int? ?? 0,
      rank: item.metadata?['rank'] as int? ?? 0,
      images: _buildImages(item),
      tags: _buildTags(item),
      alias: _buildAlias(item),
      ratingScore: (item.metadata?['ratingScore'] as num?)?.toDouble() ?? 0.0,
      votes: item.metadata?['votes'] as int? ?? 0,
      votesCount: _buildVotesCount(item),
      info: item.metadata?['info'] as String? ?? '',
    );
  }

  /// Converts any [MediaItem] into a [BangumiItem] usable by the existing
  /// video player, history and favorites pipeline.
  ///
  /// Bangumi-backed items (id "bangumi:123") are converted losslessly via
  /// [toBangumiItem]. Every other item gets a synthetic [BangumiItem] whose
  /// ID is derived deterministically from the [MediaItem.id] string, so:
  ///
  /// * watch history keys stay stable across sessions (resume works),
  /// * favorites/downloads keyed by the ID resolve consistently,
  /// * re-entering the same item always maps to the same BangumiItem.
  ///
  /// Synthetic IDs live in 901,000,000–999,999,999, far above the real
  /// Bangumi subject ID range, so they never collide with genuine subjects.
  /// Danmaku/comment lookups against these IDs simply find no match and
  /// degrade gracefully.
  static BangumiItem toPlaybackBangumiItem(MediaItem item) {
    final real = toBangumiItem(item);
    if (real != null) return real;

    return BangumiItem(
      id: syntheticBangumiId(item.id),
      type: _mediaTypeToBangumiType(item.type),
      name: item.originalTitle ?? item.title,
      nameCn: item.title,
      summary: item.description ?? '',
      airDate: item.year ?? '',
      airWeekday: 0,
      rank: 0,
      images: _buildImages(item),
      tags: const [],
      alias: const [],
      ratingScore: 0,
      votes: 0,
      votesCount: const [],
      info: '',
    );
  }

  /// Lower bound of the synthetic ID range (inclusive).
  static const int syntheticIdBase = 901000000;

  /// Derives a deterministic synthetic Bangumi subject ID for [mediaId].
  ///
  /// FNV-1a 32-bit hash of the full media ID, mapped into
  /// [syntheticIdBase, 1000000000).
  static int syntheticBangumiId(String mediaId) {
    var hash = 0x811c9dc5;
    for (var i = 0; i < mediaId.length; i++) {
      hash ^= mediaId.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return syntheticIdBase + (hash % (1000000000 - syntheticIdBase));
  }

  /// Whether [bangumiId] falls inside the synthetic ID range.
  static bool isSyntheticBangumiId(int bangumiId) =>
      bangumiId >= syntheticIdBase && bangumiId < 1000000000;

  static MediaType _bangumiTypeToMediaType(int bangumiType) {
    return switch (bangumiType) {
      2 => MediaType.anime,
      6 => MediaType.tv,
      _ => MediaType.other,
    };
  }

  static int _mediaTypeToBangumiType(MediaType mediaType) {
    return switch (mediaType) {
      MediaType.anime => 2,
      MediaType.tv => 6,
      _ => 2,
    };
  }

  static String? _extractYear(String airDate) {
    if (airDate.isEmpty) return null;
    final year = airDate.split('-').first;
    return year.isNotEmpty ? year : null;
  }

  static int? _extractBangumiId(String mediaId) {
    final parts = mediaId.split(':');
    if (parts.length < 2) return null;
    return int.tryParse(parts.last);
  }

  static Map<String, dynamic> _buildMetadata(BangumiItem item) {
    return {
      'bangumiId': item.id,
      'bangumiType': item.type,
      'airDate': item.airDate,
      'airWeekday': item.airWeekday,
      'rank': item.rank,
      'ratingScore': item.ratingScore,
      'votes': item.votes,
      'votesCount': item.votesCount,
      'info': item.info,
      if (item.alias.isNotEmpty) 'alias': item.alias,
      if (item.tags.isNotEmpty)
        'tags': item.tags.map((t) => t.toJson()).toList(),
    };
  }

  static Map<String, String> _buildImages(MediaItem item) {
    final cover = item.cover;
    return {
      'large': cover ?? '',
      'common': '',
      'medium': '',
      'small': '',
      'grid': '',
    };
  }

  static List<BangumiTag> _buildTags(MediaItem item) {
    final rawTags = item.metadata?['tags'];
    if (rawTags is! List) return [];
    return rawTags
        .whereType<Map>()
        .map((t) => BangumiTag.fromJson(Map<String, dynamic>.from(t)))
        .toList();
  }

  static List<String> _buildAlias(MediaItem item) {
    final alias = item.metadata?['alias'];
    if (alias is! List) return [];
    return alias.whereType<String>().toList();
  }

  static List<int> _buildVotesCount(MediaItem item) {
    final votes = item.metadata?['votesCount'];
    if (votes is! List) return [];
    return votes.whereType<int>().toList();
  }
}
