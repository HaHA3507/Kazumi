import 'package:kazumi/modules/media/media_type.dart';

/// A content source — an installed rule and its operational state.
///
/// Users manage sources through the Source Manager: add, remove,
/// enable/disable, reorder, import/export, test.
class MediaSource {
  /// Unique identifier (typically the rule name, lowercased).
  final String id;

  /// Display name.
  final String name;

  /// Base URL of the target website.
  final String? baseUrl;

  /// Whether this source is active (participates in search).
  final bool enabled;

  /// Sort priority (lower = higher priority in search results).
  final int priority;

  /// Rule version string.
  final String version;

  /// Content type hint from the rule.
  final MediaType type;

  /// When the rule was installed (null for bundled defaults).
  final DateTime? installedAt;

  /// When the rule was last updated.
  final DateTime? updatedAt;

  MediaSource({
    required this.id,
    required this.name,
    this.baseUrl,
    this.enabled = true,
    this.priority = 0,
    this.version = '',
    this.type = MediaType.unknown,
    this.installedAt,
    this.updatedAt,
  });

  MediaSource copyWith({
    String? id,
    String? name,
    String? baseUrl,
    bool? enabled,
    int? priority,
    String? version,
    MediaType? type,
    DateTime? installedAt,
    DateTime? updatedAt,
  }) {
    return MediaSource(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      enabled: enabled ?? this.enabled,
      priority: priority ?? this.priority,
      version: version ?? this.version,
      type: type ?? this.type,
      installedAt: installedAt ?? this.installedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() => 'MediaSource(id: $id, name: $name, enabled: $enabled)';
}
