import 'package:kazumi/modules/media/media_detail.dart';
import 'package:kazumi/modules/media/media_item.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/media/media_item_adapter.dart';

/// Universal playback arguments using [MediaItem] instead of [BangumiItem].
///
/// This is the preferred entry point for the new universal media layer.
/// [toVideoPlaybackArgs] converts to the existing [OnlineVideoPlaybackArgs]
/// so the current video page works without modification.
///
/// Bangumi-backed items convert losslessly. Every other item receives a
/// deterministic synthetic [BangumiItem] (see
/// [MediaItemAdapter.toPlaybackBangumiItem]) so history, favorites and
/// resume all keep working for arbitrary sources.
class MediaPlaybackArgs {
  const MediaPlaybackArgs({
    required this.mediaItem,
    required this.plugin,
    required this.episodeGroups,
    this.src = '',
  });

  /// The media item to play.
  final MediaItem mediaItem;

  /// The source plugin used for playback.
  final Plugin plugin;

  /// Episode groups (roads) for this item.
  final List<MediaEpisodeGroup> episodeGroups;

  /// The search result source URL (for the existing video page).
  final String src;

  /// Converts to the existing [OnlineVideoPlaybackArgs].
  OnlineVideoPlaybackArgs toVideoPlaybackArgs() {
    final bangumiItem = MediaItemAdapter.toPlaybackBangumiItem(mediaItem);

    final roads = <Road>[];
    for (final group in episodeGroups) {
      roads.add(Road(
        name: group.title,
        data: group.episodes.map((e) => e.url).toList(),
        identifier: group.episodes.map((e) => e.title).toList(),
      ));
    }

    return OnlineVideoPlaybackArgs(
      bangumiItem: bangumiItem,
      plugin: plugin,
      title: mediaItem.displayTitle,
      src: src,
      roads: roads,
    );
  }
}
