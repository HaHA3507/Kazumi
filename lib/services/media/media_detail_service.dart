import 'package:dio/dio.dart';
import 'package:kazumi/modules/media/media_detail.dart';
import 'package:kazumi/modules/media/media_item.dart';
import 'package:kazumi/modules/media/media_rule.dart';
import 'package:kazumi/services/media/media_rule_engine.dart';

/// Fetches detail page metadata (cover, description, year, genre) for a
/// media item using the rule's [RuleDetail] XPath configuration.
///
/// When a rule does not provide detail XPath fields, [queryDetail] returns
/// null — the caller should fall back to the metadata already available in
/// the [MediaItem] from search results.
class MediaDetailService {
  MediaDetailService(this._engine);

  final MediaRuleEngine _engine;

  /// Fetches detail metadata for [item] using [rule].
  ///
  /// [item] should contain a non-null [MediaItem.detailUrl] pointing to the
  /// detail page. Returns a [MediaDetail] with metadata fields populated
  /// (no episode groups), or null when the rule has no detail XPath configured.
  Future<MediaDetail?> queryDetail(
    MediaRule rule,
    MediaItem item, {
    CancelToken? cancelToken,
  }) async {
    final detailUrl = item.detailUrl;
    if (detailUrl == null || detailUrl.isEmpty) return null;

    final detail = await _engine.queryDetail(
      rule,
      detailUrl,
      cancelToken: cancelToken,
    );
    if (detail == null) return null;

    // Merge: use the detail's metadata but keep the original title/id.
    return MediaDetail(
      id: item.id,
      title: item.title,
      originalTitle: item.originalTitle,
      sourceId: item.sourceId,
      type: item.type,
      cover: detail.cover ?? item.cover,
      description: detail.description ?? item.description,
      year: detail.year ?? item.year,
      genre: detail.genre ?? item.genre,
      metadata: item.metadata,
      episodeGroups: [],
    );
  }
}
