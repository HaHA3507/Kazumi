import 'package:dio/dio.dart';
import 'package:kazumi/modules/media/media_detail.dart';
import 'package:kazumi/modules/media/media_item.dart';
import 'package:kazumi/modules/media/media_rule.dart';
import 'package:kazumi/services/media/media_rule_engine.dart';
import 'package:kazumi/services/media/media_rule_models.dart';

/// Fetches episode lists for a media item using the rule's [RuleEpisodes]
/// configuration.
///
/// Returns [MediaEpisodeGroup]s, where each group corresponds to a "road"
/// (线路) in the legacy model. Groups may represent different playback
/// sources, seasons, or quality lines depending on the rule.
class MediaEpisodeService {
  MediaEpisodeService(this._engine);

  final MediaRuleEngine _engine;

  /// Queries episodes for [item] using [rule].
  ///
  /// [item] should contain a non-null [MediaItem.detailUrl] pointing to the
  /// detail page from which episodes are extracted.
  ///
  /// Returns a [MediaEpisodeResult] containing episode groups and diagnostics.
  Future<MediaEpisodeResult> queryEpisodes(
    MediaRule rule,
    MediaItem item, {
    CancelToken? cancelToken,
  }) async {
    final detailUrl = item.detailUrl;
    if (detailUrl == null || detailUrl.isEmpty) {
      throw ArgumentError('MediaItem.detailUrl is required for episode query');
    }

    return _engine.queryEpisodes(rule, detailUrl, cancelToken: cancelToken);
  }

  /// Convenience: queries episodes and returns a flat list of all episodes
  /// across all groups. Useful for simple sources with a single group.
  Future<List<MediaEpisode>> queryAllEpisodes(
    MediaRule rule,
    MediaItem item, {
    CancelToken? cancelToken,
  }) async {
    final result = await queryEpisodes(rule, item, cancelToken: cancelToken);
    return result.groups.expand((g) => g.episodes).toList();
  }
}
