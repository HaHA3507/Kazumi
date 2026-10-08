import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/modules/media/media_item.dart';
import 'package:kazumi/repositories/collect_crud_repository.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/services/media/media_item_adapter.dart';

/// Bridges the universal [MediaItem] / [CollectedMedia] API to the existing
/// Hive-backed [HistoryRepository] and [CollectCrudRepository].
///
/// All methods convert [MediaItem] ↔ [BangumiItem] via [MediaItemAdapter]
/// and delegate to the existing repositories. This avoids modifying the
/// Hive-persisted models while enabling the new UI layer to work with
/// [MediaItem] exclusively.
///
/// For non-Bangumi items (where [MediaItemAdapter.toBangumiItem] returns
/// null), history/favorites operations are no-ops — the data layer will
/// fully support string-keyed items in a future migration phase.
class MediaHistoryAdapter {
  MediaHistoryAdapter._();

  // ---------------------------------------------------------------------------
  // History
  // ---------------------------------------------------------------------------

  /// Finds the [History] for [item] under the given [pluginName].
  /// Returns null when the item is not Bangumi-backed or not found.
  static History? getHistory(
    IHistoryRepository repo,
    MediaItem item,
    String pluginName, {
    String entryKind = HistoryEntryKind.online,
  }) {
    final bangumiItem = MediaItemAdapter.toBangumiItem(item);
    if (bangumiItem == null) return null;
    return repo.getHistory(pluginName, bangumiItem, entryKind: entryKind);
  }

  /// Returns the last-watched [Progress] for [item], or null.
  static Progress? getLastProgress(
    IHistoryRepository repo,
    MediaItem item,
    String pluginName, {
    String entryKind = HistoryEntryKind.online,
  }) {
    final bangumiItem = MediaItemAdapter.toBangumiItem(item);
    if (bangumiItem == null) return null;
    return repo.getLastWatchingProgress(
      bangumiItem,
      pluginName,
      entryKind: entryKind,
    );
  }

  /// Returns all histories as a list of [MediaItem] paired with [History].
  static List<HistoryEntry> getAllHistories(IHistoryRepository repo) {
    return repo.getAllHistories().map((h) => HistoryEntry(h, h.mediaItem)).toList();
  }

  /// Deletes the history for [item].
  static Future<void> deleteHistory(
    IHistoryRepository repo,
    MediaItem item,
    String pluginName, {
    String entryKind = HistoryEntryKind.online,
  }) async {
    final bangumiItem = MediaItemAdapter.toBangumiItem(item);
    if (bangumiItem == null) return;
    final history = repo.getHistory(pluginName, bangumiItem, entryKind: entryKind);
    if (history != null) {
      await repo.deleteHistory(history);
    }
  }

  // ---------------------------------------------------------------------------
  // Favorites / Collection
  // ---------------------------------------------------------------------------

  /// Returns the [CollectType] for [item], or [CollectType.none] when
  /// the item is not Bangumi-backed or not collected.
  static CollectType getCollectType(
    ICollectCrudRepository repo,
    MediaItem item,
  ) {
    final bangumiItem = MediaItemAdapter.toBangumiItem(item);
    if (bangumiItem == null) return CollectType.none;
    final typeInt = repo.getCollectType(bangumiItem.id);
    return CollectType.fromValue(typeInt);
  }

  /// Adds [item] to the collection with [type].
  /// No-op when [item] is not Bangumi-backed.
  static Future<void> addCollectible(
    ICollectCrudRepository repo,
    MediaItem item,
    CollectType type,
  ) async {
    final bangumiItem = MediaItemAdapter.toBangumiItem(item);
    if (bangumiItem == null) return;
    await repo.addCollectible(bangumiItem, type.value);
  }

  /// Removes [item] from the collection.
  /// No-op when [item] is not Bangumi-backed.
  static Future<void> deleteCollectible(
    ICollectCrudRepository repo,
    MediaItem item,
  ) async {
    final bangumiItem = MediaItemAdapter.toBangumiItem(item);
    if (bangumiItem == null) return;
    await repo.deleteCollectible(bangumiItem.id);
  }

  /// Returns all collected items as [MediaItem] pairs.
  static List<CollectedMediaEntry> getAllCollectibles(
    ICollectCrudRepository repo,
  ) {
    return repo.getAllCollectibles().map((c) {
      return CollectedMediaEntry(c, c.mediaItem);
    }).toList();
  }
}

/// A [History] paired with its computed [MediaItem].
class HistoryEntry {
  final History history;
  final MediaItem mediaItem;

  HistoryEntry(this.history, this.mediaItem);
}

/// A [CollectedBangumi] paired with its computed [MediaItem].
class CollectedMediaEntry {
  final CollectedBangumi collected;
  final MediaItem mediaItem;

  CollectedMediaEntry(this.collected, this.mediaItem);
}
