import 'package:kazumi/modules/media/media_type.dart';

/// Universal media item — the fundamental unit across search, history,
/// favorites and playback.
///
/// Replaces [BangumiItem] as the core domain model. Old [BangumiItem]
/// instances are converted via [BangumiItemAdapter].
///
/// The [id] is a string (not int) so it can represent Bangumi subject IDs,
/// rule-defined IDs, or any arbitrary identifier. The [sourceId] identifies
/// which rule/source produced this item.
class MediaItem {
  /// Unique identifier. Convention: `"<sourceId>:<nativeId>"` or
  /// `"bangumi:<id>"` for items adapted from Bangumi.
  final String id;

  /// Display title (e.g. Chinese name).
  final String title;

  /// Original title (e.g. Japanese name), if available.
  final String? originalTitle;

  /// Cover image URL.
  final String? cover;

  /// Description / synopsis.
  final String? description;

  /// Release year (e.g. "2024").
  final String? year;

  /// Genre label (e.g. "电视剧", "电影").
  final String? genre;

  /// Detail page URL used by the rule engine to fetch episodes.
  final String? detailUrl;

  /// ID of the source rule that produced this item.
  final String sourceId;

  /// Media type classification.
  final MediaType type;

  /// Extension metadata from rule extraction.
  /// Rule authors can store arbitrary key-value pairs here.
  final Map<String, dynamic>? metadata;

  MediaItem({
    required this.id,
    required this.title,
    required this.sourceId,
    this.type = MediaType.unknown,
    this.originalTitle,
    this.cover,
    this.description,
    this.year,
    this.genre,
    this.detailUrl,
    this.metadata,
  });

  MediaItem copyWith({
    String? id,
    String? title,
    String? sourceId,
    MediaType? type,
    String? originalTitle,
    String? cover,
    String? description,
    String? year,
    String? genre,
    String? detailUrl,
    Map<String, dynamic>? metadata,
  }) {
    return MediaItem(
      id: id ?? this.id,
      title: title ?? this.title,
      sourceId: sourceId ?? this.sourceId,
      type: type ?? this.type,
      originalTitle: originalTitle ?? this.originalTitle,
      cover: cover ?? this.cover,
      description: description ?? this.description,
      year: year ?? this.year,
      genre: genre ?? this.genre,
      detailUrl: detailUrl ?? this.detailUrl,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Best display title: prefer [title], fall back to [originalTitle].
  String get displayTitle => title.isNotEmpty ? title : (originalTitle ?? title);

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    return MediaItem(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      sourceId: json['sourceId'] as String? ?? '',
      type: MediaType.fromString(json['type'] as String?),
      originalTitle: json['originalTitle'] as String?,
      cover: json['cover'] as String?,
      description: json['description'] as String?,
      year: json['year'] as String?,
      genre: json['genre'] as String?,
      detailUrl: json['detailUrl'] as String?,
      metadata: json['metadata'] is Map
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'sourceId': sourceId,
        'type': type.name,
        if (originalTitle != null) 'originalTitle': originalTitle,
        if (cover != null) 'cover': cover,
        if (description != null) 'description': description,
        if (year != null) 'year': year,
        if (genre != null) 'genre': genre,
        if (detailUrl != null) 'detailUrl': detailUrl,
        if (metadata != null) 'metadata': metadata,
      };

  @override
  String toString() => 'MediaItem(id: $id, title: $title, sourceId: $sourceId)';
}
