import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:kazumi/modules/media/media_detail.dart';
import 'package:kazumi/modules/media/media_item.dart';
import 'package:kazumi/modules/media/media_rule.dart';
import 'package:kazumi/services/media/media_rule_models.dart';
import 'package:kazumi/services/plugin/rule_engine.dart' as legacy;
import 'package:kazumi/utils/episode_url.dart';
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';

/// Universal rule engine that accepts [MediaRule] and produces [MediaItem]
/// / [MediaEpisodeGroup] results.
///
/// Internally delegates to the proven [legacy.RuleEngine] for HTTP execution
/// and XPath/API parsing, then enriches the results with [MediaItem] metadata
/// from the new v9 schema fields (cover, description, year).
///
/// Legacy rules (v8) are fully supported — they produce [MediaItem]s with
/// only `title` and `detailUrl` populated (same as the old [SearchItem]).
class MediaRuleEngine {
  MediaRuleEngine({
    legacy.RuleEngine? legacyEngine,
    bool logFailures = true,
  }) : _legacy = legacyEngine ?? legacy.RuleEngine(logFailures: logFailures);

  final legacy.RuleEngine _legacy;

  /// Search for media items using the rule.
  ///
  /// [keyword] is substituted into the search URL template.
  /// Returns [MediaSearchResult] with [MediaItem]s containing title, detailUrl,
  /// and optionally cover/description/year when the rule provides those XPath fields.
  Future<MediaSearchResult> search(
    MediaRule rule,
    String keyword, {
    CancelToken? cancelToken,
  }) async {
    final config = MediaRuleExecutionConfig.fromRule(rule);

    final trace = await _legacy.search(
      config.toLegacyConfig(),
      keyword,
      cancelToken: cancelToken,
    );

    // Convert SearchItem[] → MediaItem[]
    final items = <MediaItem>[];
    for (final searchItem in trace.response.data) {
      items.add(MediaItem(
        id: '${rule.id}:${searchItem.src}',
        title: searchItem.name,
        sourceId: rule.id,
        type: rule.type,
        detailUrl: _resolveDetailUrl(config.baseUrl, searchItem.src),
      ));
    }

    // Enrich with cover/description/year from v9 XPath fields if available.
    if (items.isNotEmpty &&
        (config.searchCoverXPath != null ||
            config.searchDescriptionXPath != null ||
            config.searchYearXPath != null)) {
      _enrichSearchItems(
        items,
        trace.rawResponse,
        config,
      );
    }

    return MediaSearchResult(
      items: items,
      diagnostics: trace.diagnostics,
      rawResponse: trace.rawResponse,
    );
  }

  /// Query episodes from a detail page URL using the rule.
  ///
  /// Returns [MediaEpisodeResult] with [MediaEpisodeGroup]s. Each group
  /// corresponds to a "road" (线路) in the legacy model.
  Future<MediaEpisodeResult> queryEpisodes(
    MediaRule rule,
    String detailUrl, {
    CancelToken? cancelToken,
  }) async {
    final config = MediaRuleExecutionConfig.fromRule(rule);

    final trace = await _legacy.queryChapters(
      config.toLegacyConfig(),
      detailUrl,
      cancelToken: cancelToken,
    );

    // Convert Road[] → MediaEpisodeGroup[]
    final groups = <MediaEpisodeGroup>[];
    for (var i = 0; i < trace.roads.length; i++) {
      final road = trace.roads[i];
      final episodes = <MediaEpisode>[];
      for (var j = 0; j < road.data.length; j++) {
        episodes.add(MediaEpisode(
          id: '${i}_$j',
          title: j < road.identifier.length ? road.identifier[j] : '第${j + 1}集',
          url: road.data[j],
          sourceId: rule.id,
          group: 'group_$i',
        ));
      }
      groups.add(MediaEpisodeGroup(
        id: 'group_$i',
        title: road.name,
        episodes: episodes,
      ));
    }

    return MediaEpisodeResult(
      groups: groups,
      diagnostics: trace.diagnostics,
      rawResponse: trace.rawResponse,
    );
  }

  /// Parse detail page metadata (cover, description, year, genre) when the
  /// rule provides detail XPath fields.
  ///
  /// Returns a partial [MediaDetail] with only the metadata fields populated
  /// (no episode groups). Call [queryEpisodes] separately for episodes.
  Future<MediaDetail?> queryDetail(
    MediaRule rule,
    String detailUrl, {
    CancelToken? cancelToken,
  }) async {
    final config = MediaRuleExecutionConfig.fromRule(rule);

    // If no detail XPath fields are configured, return null.
    if (config.detailCoverXPath == null &&
        config.detailDescriptionXPath == null &&
        config.detailYearXPath == null &&
        config.detailGenreXPath == null) {
      return null;
    }

    // Fetch the detail page.
    // We reuse the legacy engine's chapter request infrastructure
    // (GET without cookies, same as XPath chapter requests).
    final trace = await _legacy.queryChapters(
      config.toLegacyConfig(),
      detailUrl,
      cancelToken: cancelToken,
    );

    // Parse the HTML for detail metadata.
    final root = _documentElement(trace.rawResponse);
    final cover = _extractXPath(root, config.detailCoverXPath);
    final description = _extractXPath(root, config.detailDescriptionXPath);
    final year = _extractXPath(root, config.detailYearXPath);
    final genre = _extractXPath(root, config.detailGenreXPath);

    return MediaDetail(
      id: '${rule.id}:$detailUrl',
      title: '', // Caller should already have the title from search
      sourceId: rule.id,
      type: rule.type,
      cover: cover,
      description: description,
      year: year,
      genre: genre,
      episodeGroups: [],
    );
  }

  /// Try to parse HTML harvested from a captcha webview as a search result.
  /// Delegates to the legacy engine's [tryParseHarvestedSearch].
  List<MediaItem>? tryParseHarvestedSearch(MediaRule rule, String html) {
    final config = MediaRuleExecutionConfig.fromRule(rule);
    final response = _legacy.tryParseHarvestedSearch(
      config.toLegacyConfig(),
      html,
    );
    if (response == null) return null;

    return response.data
        .map((item) => MediaItem(
              id: '${rule.id}:${item.src}',
              title: item.name,
              sourceId: rule.id,
              type: rule.type,
              detailUrl: _resolveDetailUrl(config.baseUrl, item.src),
            ))
        .toList();
  }

  void _enrichSearchItems(
    List<MediaItem> items,
    String rawHtml,
    MediaRuleExecutionConfig config,
  ) {
    final root = _documentElement(rawHtml);
    final nodes = root.queryXPath(config.searchList).nodes;

    if (nodes.length != items.length) {
      // Node count mismatch — skip enrichment, the base items are still valid.
      return;
    }

    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final item = items[i];

      if (config.searchCoverXPath != null) {
        final cover = _extractFromXPathNode(node, config.searchCoverXPath!);
        if (cover != null) items[i] = item.copyWith(cover: cover);
      }
      if (config.searchDescriptionXPath != null) {
        final desc = _extractFromXPathNode(node, config.searchDescriptionXPath!);
        if (desc != null) items[i] = items[i].copyWith(description: desc);
      }
      if (config.searchYearXPath != null) {
        final year = _extractFromXPathNode(node, config.searchYearXPath!);
        if (year != null) items[i] = items[i].copyWith(year: year);
      }
    }
  }

  String? _resolveDetailUrl(String baseUrl, String src) {
    if (src.isEmpty) return null;
    return normalizeEpisodeUrl(baseUrl, src);
  }

  Element _documentElement(String raw) {
    final element = parse(raw).documentElement;
    if (element == null) {
      throw StateError('HTML response has no root element');
    }
    return element;
  }

  String? _extractXPath(Element root, String? xpath) {
    if (xpath == null || xpath.trim().isEmpty) return null;
    final node = root.queryXPath(xpath).node;
    if (node == null) return null;
    final text = node.text?.trim();
    if (text != null && text.isNotEmpty) return text;
    final attrs = node.attributes.values;
    return attrs.isNotEmpty ? attrs.first.trim() : null;
  }

  String? _extractFromXPathNode(XPathNode<Node> parent, String xpath) {
    if (xpath.trim().isEmpty) return null;
    final node = parent.queryXPath(xpath).node;
    if (node == null) return null;
    final text = node.text?.trim();
    if (text != null && text.isNotEmpty) return text;
    final attrs = node.attributes.values;
    return attrs.isNotEmpty ? attrs.first.trim() : null;
  }
}
