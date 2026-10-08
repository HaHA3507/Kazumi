import 'dart:async';

import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:kazumi/modules/media/media_rule.dart';
import 'package:kazumi/modules/media/media_stream.dart';
import 'package:kazumi/plugins/api_rule_config.dart';
import 'package:kazumi/request/clients/plugin_site_client.dart';
import 'package:kazumi/services/media/media_rule_models.dart';
import 'package:kazumi/services/video_source/video_source_service.dart';
import 'package:kazumi/services/video_source/webview_video_source_service.dart';
import 'package:kazumi/utils/episode_url.dart';
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';

/// Resolves playable [MediaStream] from an episode page URL.
///
/// Supports two resolution modes:
/// * **xpath** — extracts the stream URL directly from the play page HTML
///   using an XPath expression configured in the rule. Fast and lightweight,
///   no WebView required.
/// * **webview** — loads the episode page in a headless WebView and
///   intercepts network traffic to detect m3u8/mp4 URLs. Delegates to the
///   existing [WebViewVideoSourceService].
///
/// When the rule does not configure a stream section, defaults to
/// **webview** mode.
class MediaStreamResolver {
  MediaStreamResolver({WebViewVideoSourceService? webviewService})
      : _webviewService = webviewService;

  WebViewVideoSourceService? _webviewService;
  StreamController<String>? _logController;

  /// Log stream for diagnostic messages.
  Stream<String> get onLog {
    _logController ??= StreamController<String>.broadcast();
    return _logController!.stream;
  }

  void _log(String message) {
    if (_logController != null && !_logController!.isClosed) {
      _logController!.add(message);
    }
  }

  /// Resolve a playable stream from the episode page URL.
  ///
  /// [rule] provides the stream resolution configuration.
  /// [episodeUrl] is the play page URL (typically from a [MediaEpisode]).
  /// [offset] is the resume position in seconds (for webview mode).
  /// [timeout] applies to webview mode only.
  Future<MediaStream> resolve(
    MediaRule rule,
    String episodeUrl, {
    int offset = 0,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final config = MediaRuleExecutionConfig.fromRule(rule);

    if (config.streamMode == 'xpath' && config.streamUrlXPath != null) {
      return _resolveWithXPath(
        config,
        episodeUrl,
        rule,
      );
    }

    // Default: WebView-based resolution.
    return _resolveWithWebview(
      config,
      episodeUrl,
      offset: offset,
      timeout: timeout,
    );
  }

  /// XPath-based stream resolution: fetch the play page HTML and extract
  /// the stream URL using the configured XPath expression.
  Future<MediaStream> _resolveWithXPath(
    MediaRuleExecutionConfig config,
    String episodeUrl,
    MediaRule rule,
  ) async {
    final url = _renderUrl(config.streamUrlXPath!, episodeUrl);

    _log('XPath stream resolution: fetching $url');
    final raw = await PluginSiteClient.instance.requestText(url, method: 'GET');

    _log('XPath stream resolution: parsing HTML (${raw.length} bytes)');
    final root = _documentElement(raw);
    final streamUrl = _extractStreamUrl(root, config.streamUrlXPath!);

    if (streamUrl == null || streamUrl.isEmpty) {
      throw const VideoSourceNotFoundException(
        'XPath stream URL not found in page',
      );
    }

    final resolvedUrl = normalizeEpisodeUrl(config.baseUrl, streamUrl);

    _log('XPath stream resolution: found $resolvedUrl');

    return MediaStream(
      url: resolvedUrl,
      format: _guessFormat(resolvedUrl),
      userAgent: rule.player?.userAgent,
      referer: rule.player?.referer ?? config.baseUrl,
      offsetSeconds: offset,
    );
  }

  /// WebView-based stream resolution: delegate to the existing
  /// [WebViewVideoSourceService].
  Future<MediaStream> _resolveWithWebview(
    MediaRuleExecutionConfig config,
    String episodeUrl, {
    required int offset,
    required Duration timeout,
  }) async {
    _webviewService ??= WebViewVideoSourceService();

    _log('WebView stream resolution: loading $episodeUrl');
    final videoSource = await _webviewService!.resolve(
      episodeUrl,
      useLegacyParser: config.streamUseLegacyParser,
      offset: offset,
      timeout: timeout,
    );

    return MediaStream(
      url: videoSource.url,
      format: videoSource.format == VideoSourceFormat.hls ? 'hls' : null,
      offsetSeconds: videoSource.offset,
    );
  }

  /// Render the stream URL template, replacing {episode_url} with the
  /// actual episode URL.
  String _renderUrl(String template, String episodeUrl) {
    return template.replaceAll('{episode_url}', episodeUrl);
  }

  /// Extract the stream URL from the HTML root using the configured XPath.
  /// The XPath may match an attribute (e.g. //source/@src) or a text node.
  String? _extractStreamUrl(Element root, String xpath) {
    final node = root.queryXPath(xpath).node;
    if (node == null) return null;
    final text = node.text?.trim();
    if (text != null && text.isNotEmpty) return text;
    final attrs = node.attributes.values;
    return attrs.isNotEmpty ? attrs.first.trim() : null;
  }

  String? _guessFormat(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.m3u8') || lower.contains('m3u8')) return 'hls';
    if (lower.contains('.mpd')) return 'dash';
    if (lower.contains('.mp4')) return 'mp4';
    return null;
  }

  Element _documentElement(String raw) {
    final element = parse(raw).documentElement;
    if (element == null) {
      throw StateError('HTML response has no root element');
    }
    return element;
  }

  /// Cancel any ongoing WebView-based resolution.
  void cancel() {
    _webviewService?.cancel();
  }

  /// Release resources.
  Future<void> dispose() async {
    await _webviewService?.dispose();
    _webviewService = null;
    if (_logController != null && !_logController!.isClosed) {
      await _logController!.close();
    }
  }
}
