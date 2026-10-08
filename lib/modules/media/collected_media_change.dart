/// Change log entry for media collection sync — replaces
/// [CollectedBangumiChange].
///
/// Actions: 1 = add, 2 = update, 3 = delete.
/// Collection types follow [CollectType] convention:
/// 1 = watching, 2 = planToWatch, 3 = onHold, 4 = watched, 5 = abandoned.
class CollectedMediaChange {
  /// Timestamp-based unique ID (seconds), used as the Hive box key.
  final int id;

  /// Media item ID (string, not int — supports non-Bangumi items).
  final String mediaId;

  /// 1 = add, 2 = update, 3 = delete.
  final int action;

  /// Collection type value.
  final int type;

  /// Event timestamp (seconds).
  final int timestamp;

  CollectedMediaChange({
    required this.id,
    required this.mediaId,
    required this.action,
    required this.type,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'mediaId': mediaId,
        'action': action,
        'type': type,
        'timestamp': timestamp,
      };

  factory CollectedMediaChange.fromJson(Map<String, dynamic> json) {
    return CollectedMediaChange(
      id: json['id'] as int,
      mediaId: json['mediaId'] as String,
      action: json['action'] as int,
      type: json['type'] as int,
      timestamp: json['timestamp'] as int,
    );
  }

  @override
  String toString() =>
      'CollectedMediaChange(id: $id, mediaId: $mediaId, action: $action)';
}
