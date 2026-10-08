/// A resolved playable stream URL with associated playback configuration.
///
/// Produced by a stream resolver (XPath extraction or WebView interception).
/// The player accepts this as its sole input — it does not know or care
/// whether the content is anime, TV, movie, etc.
class MediaStream {
  /// The playable URL (m3u8, mp4, mpd, or direct media URL).
  final String url;

  /// Quality label (e.g. "1080p", "720p", "高清").
  final String? quality;

  /// Stream format: "mp4", "hls", "dash", or null for auto-detection.
  final String? format;

  /// HTTP request headers for the media player.
  final Map<String, String>? headers;

  /// Referer header for the media request.
  final String? referer;

  /// User-Agent header for the media request.
  final String? userAgent;

  /// Whether this is a live stream.
  final bool isLive;

  /// Optional start offset in seconds (for history resume).
  final int? offsetSeconds;

  MediaStream({
    required this.url,
    this.quality,
    this.format,
    this.headers,
    this.referer,
    this.userAgent,
    this.isLive = false,
    this.offsetSeconds,
  });

  @override
  String toString() => 'MediaStream(url: $url, format: $format, quality: $quality)';
}
