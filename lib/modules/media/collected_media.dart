import 'package:kazumi/modules/media/media_item.dart';

/// Local media collection entry — replaces [CollectedBangumi].
///
/// Stored in the `collectibles` Hive box (new typeId). The old
/// [CollectedBangumi] box is preserved for migration.
///
/// Collection types follow the same integer convention as [CollectType]:
/// 1 = watching, 2 = planToWatch, 3 = onHold, 4 = watched, 5 = abandoned.
class CollectedMedia {
  /// The collected media item.
  final MediaItem mediaItem;

  /// Collection timestamp.
  final DateTime time;

  /// Collection type (see [CollectType] values).
  final int type;

  CollectedMedia({
    required this.mediaItem,
    required this.time,
    required this.type,
  });

  /// Hive box key — the media item ID.
  String get key => mediaItem.id;

  static String getKey(MediaItem item) => item.id;

  CollectedMedia copyWith({MediaItem? mediaItem, DateTime? time, int? type}) {
    return CollectedMedia(
      mediaItem: mediaItem ?? this.mediaItem,
      time: time ?? this.time,
      type: type ?? this.type,
    );
  }

  Map<String, dynamic> toJson() => {
        'mediaItem': mediaItem.toJson(),
        'time': time.toIso8601String(),
        'type': type,
      };

  factory CollectedMedia.fromJson(Map<String, dynamic> json) {
    return CollectedMedia(
      mediaItem: MediaItem.fromJson(
          Map<String, dynamic>.from(json['mediaItem'] as Map)),
      time: DateTime.parse(json['time'] as String),
      type: json['type'] as int,
    );
  }

  @override
  String toString() =>
      'CollectedMedia(type: $type, time: $time, media: ${mediaItem.title})';
}
