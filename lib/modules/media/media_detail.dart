import 'package:kazumi/modules/media/media_item.dart';
import 'package:kazumi/modules/media/media_type.dart';

/// A single playable episode within a [MediaEpisodeGroup].
class MediaEpisode {
  /// Episode identifier within the group (e.g. "1", "EP1", "第1集").
  final String id;

  /// Display title for this episode.
  final String title;

  /// Playback page URL (may be a direct media URL or a page requiring
  /// further resolution via [MediaStreamResolver]).
  final String url;

  /// Optional thumbnail URL.
  final String? thumbnail;

  /// Source rule ID that produced this episode.
  final String sourceId;

  /// Group ID this episode belongs to.
  final String? group;

  MediaEpisode({
    required this.id,
    required this.title,
    required this.url,
    required this.sourceId,
    this.thumbnail,
    this.group,
  });

  @override
  String toString() => 'MediaEpisode(id: $id, title: $title, url: $url)';
}

/// A named group of episodes (e.g. "线路1", "第一季", "Main").
///
/// For simple sources with no grouping, a single default group is used.
/// For movies, the group typically contains a single episode.
class MediaEpisodeGroup {
  /// Group identifier.
  final String id;

  /// Group display title (e.g. "线路1", "Season 1", "播放线路1").
  final String title;

  /// Episodes in this group, in playback order.
  final List<MediaEpisode> episodes;

  MediaEpisodeGroup({
    required this.id,
    required this.title,
    required this.episodes,
  });

  @override
  String toString() =>
      'MediaEpisodeGroup(id: $id, title: $title, ${episodes.length} episodes)';
}

/// Detailed information about a media item, obtained by parsing the detail
/// page URL. Extends [MediaItem] with richer metadata and episode groups.
class MediaDetail {
  final String id;
  final String title;
  final String? originalTitle;
  final String? cover;
  final String? description;
  final String? year;
  final String? genre;
  final String? rating;
  final String? tags;
  final String sourceId;
  final MediaType type;
  final Map<String, dynamic>? metadata;

  /// Episode groups parsed from the detail page.
  final List<MediaEpisodeGroup> episodeGroups;

  MediaDetail({
    required this.id,
    required this.title,
    required this.sourceId,
    this.type = MediaType.unknown,
    this.originalTitle,
    this.cover,
    this.description,
    this.year,
    this.genre,
    this.rating,
    this.tags,
    this.metadata,
    this.episodeGroups = const [],
  });

  /// Convert to a [MediaItem] for use in search/history/favorites.
  MediaItem toItem() => MediaItem(
        id: id,
        title: title,
        sourceId: sourceId,
        type: type,
        originalTitle: originalTitle,
        cover: cover,
        description: description,
        year: year,
        genre: genre,
        detailUrl: null,
        metadata: metadata,
      );

  @override
  String toString() =>
      'MediaDetail(id: $id, title: $title, ${episodeGroups.length} groups)';
}
