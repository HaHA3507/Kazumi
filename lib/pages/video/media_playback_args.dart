import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/media/media_detail.dart';
import 'package:kazumi/modules/media/media_item.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/media/bangumi_item_adapter.dart';

/// Universal playback arguments using [MediaItem] instead of [BangumiItem].
///
/// This is the preferred entry point for the new universal media layer.
/// When the [MediaItem] is Bangumi-backed, [toVideoPlaybackArgs] converts
/// to the existing [OnlineVideoPlaybackArgs] so the current video page
/// works without modification.
///
/// For non-Bangumi items, [toVideoPlaybackArgs] returns null — the video
/// page will be fully migrated to accept [MediaPlaybackArgs] in a future
/// phase.
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

  /// Converts to the existing [OnlineVideoPlaybackArgs] when the
  /// [MediaItem] is Bangumi-backed. Returns null for non-Bangumi items.
  OnlineVideoPlaybackArgs? toVideoPlaybackArgs() {
    final bangumiItem = BangumiItemAdapter.toBangumiItem(mediaItem);
    if (bangumiItem == null) return null;

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
