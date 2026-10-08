import 'package:kazumi/modules/media/media_item.dart';

/// A group of [MediaItem]s from different sources that represent the same
/// content (same title, optionally same year).
///
/// The [primary] item is the best representative — typically the first result
/// found, or the one with the most metadata (cover, description, etc.).
/// [variants] contains all items in the group, including [primary].
class DeduplicatedMediaItem {
  final MediaItem primary;
  final List<MediaItem> variants;

  DeduplicatedMediaItem({required this.primary, required this.variants});

  String get title => primary.displayTitle;
  String? get cover => primary.cover;
  String? get description => primary.description;
  String? get year => primary.year;
  String? get genre => primary.genre;

  /// All source IDs that returned this content.
  List<String> get sourceIds =>
      variants.map((v) => v.sourceId).toList(growable: false);

  /// Whether this content is available from multiple sources.
  bool get hasMultipleSources => variants.length > 1;

  @override
  String toString() =>
      'DeduplicatedMediaItem(title: $title, sources: ${sourceIds.length})';
}

/// Deduplicates [MediaItem]s across multiple sources by normalized title.
///
/// Normalization:
/// * Trim whitespace
/// * Lowercase for comparison
/// * Strip common separators (·, -, :, etc.)
/// * Optional year matching when both items have a year
///
/// Items from the same source are never deduplicated against each other.
class MediaDeduplicator {
  const MediaDeduplicator();

  /// Deduplicates a flat list of [MediaItem]s into groups.
  ///
  /// Returns a list of [DeduplicatedMediaItem]s sorted by group size
  /// (largest groups first), then by title.
  List<DeduplicatedMediaItem> deduplicate(List<MediaItem> items) {
    final groups = <String, List<MediaItem>>{};

    for (final item in items) {
      final key = _normalizeKey(item);
      groups.putIfAbsent(key, () => []).add(item);
    }

    final result = <DeduplicatedMediaItem>[];
    for (final group in groups.values) {
      result.add(DeduplicatedMediaItem(
        primary: _pickBest(group),
        variants: group,
      ));
    }

    // Sort: groups with more sources first, then by title.
    result.sort((a, b) {
      final sourceCompare = b.variants.length.compareTo(a.variants.length);
      if (sourceCompare != 0) return sourceCompare;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    return result;
  }

  /// Picks the best representative item from a group.
  /// Prefers items with cover, description, and year.
  MediaItem _pickBest(List<MediaItem> group) {
    var best = group.first;
    var bestScore = _metadataScore(best);
    for (var i = 1; i < group.length; i++) {
      final item = group[i];
      final score = _metadataScore(item);
      if (score > bestScore) {
        best = item;
        bestScore = score;
      }
    }
    return best;
  }

  /// Scores an item by how much metadata it has (for "best" selection).
  int _metadataScore(MediaItem item) {
    var score = 0;
    if (item.cover != null) score += 4;
    if (item.description != null && item.description!.isNotEmpty) score += 2;
    if (item.year != null) score += 1;
    if (item.genre != null) score += 1;
    return score;
  }

  /// Normalizes a title for comparison.
  ///
  /// This is intentionally conservative — only basic normalization is applied.
  /// More aggressive normalization (stripping season suffixes, etc.) can be
  /// added later without breaking the interface.
  String _normalizeKey(MediaItem item) {
    var title = item.displayTitle.toLowerCase().trim();
    // Remove common separators.
    title = title.replaceAll(RegExp(r'[\s·\-:：_\u00b7\u2027]'), '');
    // When a year is available, include it in the key to prevent merging
    // different releases (e.g. "庆余年 2019" vs "庆余年 2024").
    final year = item.year;
    if (year != null && year.isNotEmpty) {
      return '$title|$year';
    }
    return title;
  }
}
