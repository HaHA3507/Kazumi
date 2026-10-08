import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/media/media_item.dart';
import 'package:kazumi/services/media/bangumi_item_adapter.dart';

part 'history_module.g.dart';

class HistoryEntryKind {
  static const String online = 'online';
  static const String offline = 'offline';

  static String normalize(String value) {
    return value == offline ? offline : online;
  }

  HistoryEntryKind._();
}

class PlaybackHistoryIdentity {
  const PlaybackHistoryIdentity({
    required this.bangumiItem,
    required this.pluginName,
    required this.episodeNumber,
    required this.episodeTitle,
    required this.road,
    required this.entryKind,
    this.onlineBangumiSrc = '',
    this.episodePageUrl = '',
  });

  final BangumiItem bangumiItem;
  final String pluginName;
  final int episodeNumber;
  final String episodeTitle;
  final int road;
  final String entryKind;
  final String onlineBangumiSrc;
  final String episodePageUrl;

  bool get canRecord => pluginName.isNotEmpty && episodeNumber > 0;

  factory PlaybackHistoryIdentity.online({
    required BangumiItem bangumiItem,
    required String pluginName,
    required int episodeNumber,
    required String episodeTitle,
    required int road,
    required String onlineBangumiSrc,
    required String episodePageUrl,
  }) {
    return PlaybackHistoryIdentity(
      bangumiItem: bangumiItem,
      pluginName: pluginName,
      episodeNumber: episodeNumber,
      episodeTitle: episodeTitle,
      road: road,
      entryKind: HistoryEntryKind.online,
      onlineBangumiSrc: onlineBangumiSrc,
      episodePageUrl: episodePageUrl,
    );
  }

  factory PlaybackHistoryIdentity.offline({
    required BangumiItem bangumiItem,
    required String pluginName,
    required int episodeNumber,
    required String episodeTitle,
    required int road,
    required String episodePageUrl,
  }) {
    return PlaybackHistoryIdentity(
      bangumiItem: bangumiItem,
      pluginName: pluginName,
      episodeNumber: episodeNumber,
      episodeTitle: episodeTitle,
      road: road,
      entryKind: HistoryEntryKind.offline,
      episodePageUrl: episodePageUrl,
    );
  }
}

@HiveType(typeId: 1)
class History {
  @HiveField(0)
  Map<int, Progress> progresses = {};

  @HiveField(1)
  int lastWatchEpisode;

  @HiveField(2)
  String adapterName;

  @HiveField(3)
  BangumiItem bangumiItem;

  @HiveField(4)
  DateTime lastWatchTime;

  @HiveField(5)
  String lastSrc;

  @HiveField(6, defaultValue: '')
  String lastWatchEpisodeName;

  @HiveField(7, defaultValue: HistoryEntryKind.online)
  String entryKind;

  @HiveField(8, defaultValue: '')
  String episodePageUrl;

  String get key => scopedKey(adapterName, bangumiItem, entryKind);

  History(
    this.bangumiItem,
    this.lastWatchEpisode,
    this.adapterName,
    this.lastWatchTime,
    this.lastSrc,
    this.lastWatchEpisodeName, {
    this.entryKind = HistoryEntryKind.online,
    this.episodePageUrl = '',
  });

  static String legacyKey(String n, BangumiItem s) => n + s.id.toString();

  static String scopedKey(String n, BangumiItem s, String entryKind) {
    return '${legacyKey(n, s)}::${HistoryEntryKind.normalize(entryKind)}';
  }

  static String getKey(
    String n,
    BangumiItem s, {
    String entryKind = HistoryEntryKind.online,
  }) {
    return scopedKey(n, s, entryKind);
  }

  @override
  String toString() {
    return 'Adapter: $adapterName, anime: ${bangumiItem.name}';
  }

  /// Computed [MediaItem] from the embedded [BangumiItem].
  /// This is a read-only getter — Hive serialization is unaffected.
  MediaItem get mediaItem =>
      BangumiItemAdapter.fromBangumiItem(bangumiItem, sourceId: adapterName);

  /// A stable string ID for this history entry's media item.
  String get mediaItemId => mediaItem.id;

  /// Episode name for the last watched episode, falling back to a default.
  String get displayEpisodeName =>
      lastWatchEpisodeName.isNotEmpty ? lastWatchEpisodeName : '第${lastWatchEpisode}集';

  /// Progress fraction (0.0 – 1.0) for the last watched episode.
  /// Returns 0 when no progress is recorded.
  double get lastProgressFraction {
    final progress = progresses[lastWatchEpisode];
    if (progress == null) return 0;
    // We don't have the total duration stored on History, so we can't
    // compute a precise fraction. Return a non-zero value to indicate
    // progress exists.
    return progress.progress.inMilliseconds > 0 ? 1 : 0;
  }

  /// Whether this history entry has any playback progress.
  bool get hasProgress => progresses.isNotEmpty && lastWatchEpisode > 0;
}

@HiveType(typeId: 2)
class Progress {
  @HiveField(0)
  int episode;

  @HiveField(1)
  int road;

  @HiveField(2)
  int _progressInMilli;

  @HiveField(3, defaultValue: 0)
  int updatedAtMs;

  Duration get progress => Duration(milliseconds: _progressInMilli);

  set progress(Duration d) => _progressInMilli = d.inMilliseconds;

  Progress(
    this.episode,
    this.road,
    this._progressInMilli, {
    this.updatedAtMs = 0,
  });

  int effectiveUpdatedAtMs(DateTime fallback) {
    return updatedAtMs > 0 ? updatedAtMs : fallback.millisecondsSinceEpoch;
  }

  @override
  String toString() {
    return 'Episode ${episode.toString()}, progress $progress';
  }
}
