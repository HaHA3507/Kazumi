import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:kazumi/modules/media/media_detail.dart';
import 'package:kazumi/modules/media/media_item.dart';
import 'package:kazumi/modules/media/media_rule.dart';
import 'package:kazumi/plugins/api_rule_config.dart' show RuleMode;
import 'package:kazumi/services/media/media_rule_models.dart';
import 'package:kazumi/services/plugin/rule_engine.dart' as legacy;
import 'package:kazumi/utils/episode_url.dart';
import 'package:xpath_selector/xpath_selector.dart';
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

    // Heuristic cover fallback: pull the first <img> out of each search
    // result node so legacy rules (no cover XPath configured) still show
    // posters in search results.
    if (items.isNotEmpty) {
      _heuristicCoverFallback(items, trace.rawResponse, config);
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
    if (config.searchMode != RuleMode.xpath) return;
    final nodes = _searchNodes(rawHtml, config);
    if (nodes == null) return;

    // Walk nodes in lockstep with the legacy parser: it skips nodes that
    // lack a name or href, so the item cursor only advances on nodes that
    // actually produced an item.
    var itemIndex = 0;
    for (final node in nodes) {
      if (itemIndex >= items.length) break;
      if (!_nodeProducesItem(node, config)) continue;
      var item = items[itemIndex];
      itemIndex++;

      if (config.searchCoverXPath != null) {
        final cover = _extractFromXPathNode(node, config.searchCoverXPath!);
        if (cover != null) item = item.copyWith(cover: cover);
      }
      if (config.searchDescriptionXPath != null) {
        final desc = _extractFromXPathNode(node, config.searchDescriptionXPath!);
        if (desc != null) item = item.copyWith(description: desc);
      }
      if (config.searchYearXPath != null) {
        final year = _extractFromXPathNode(node, config.searchYearXPath!);
        if (year != null) item = item.copyWith(year: year);
      }
      items[itemIndex - 1] = item;
    }
  }

  /// Extracts cover images for search results that lack one, without any
  /// rule configuration: within each search result node, find the first
  /// `<img>` and read its real image URL from common lazy-loading
  /// attributes (data-original/data-src/...) before falling back to src.
  void _heuristicCoverFallback(
    List<MediaItem> items,
    String rawHtml,
    MediaRuleExecutionConfig config,
  ) {
    if (items.every((item) => item.cover != null && item.cover!.isNotEmpty)) {
      return;
    }
    if (config.searchMode != RuleMode.xpath) return;
    final nodes = _searchNodes(rawHtml, config);
    if (nodes == null) return;

    var itemIndex = 0;
    for (final node in nodes) {
      if (itemIndex >= items.length) break;
      if (!_nodeProducesItem(node, config)) continue;
      final item = items[itemIndex];
      itemIndex++;
      if (item.cover != null && item.cover!.isNotEmpty) continue;
      final cover = _firstImageInNode(node, config.baseUrl);
      if (cover != null) items[itemIndex - 1] = item.copyWith(cover: cover);
    }
  }

  List<XPathNode<Node>>? _searchNodes(
    String rawHtml,
    MediaRuleExecutionConfig config,
  ) {
    final searchList = config.searchList.trim();
    if (searchList.isEmpty) return null;
    try {
      final root = _documentElement(rawHtml);
      return root.queryXPath(searchList).nodes;
    } catch (_) {
      return null;
    }
  }

  /// Mirrors the legacy parser's validity check so the node-to-item cursor
  /// stays aligned when the parser skipped nodes.
  bool _nodeProducesItem(
    XPathNode<Node> node,
    MediaRuleExecutionConfig config,
  ) {
    try {
      final name = node.queryXPath(config.searchName).node?.text?.trim() ?? '';
      final href =
          node.queryXPath(config.searchResult).node?.attributes['href']
              ?.trim() ??
          '';
      return name.isNotEmpty && href.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  String? _firstImageInNode(XPathNode<Node> node, String baseUrl) {
    // Pass 1: real <img> tags. Lazy-loading sites put the real image in
    // data-* attributes while src holds a placeholder, so prefer them
    // before falling back to src.
    List<XPathNode<Node>> imgs;
    try {
      imgs = node.queryXPath('.//img').nodes;
    } catch (_) {
      imgs = const [];
    }
    const lazyAttributes = [
      'data-original',
      'data-src',
      'data-lazy-src',
      'data-echo',
      'data-bg',
    ];
    for (final img in imgs) {
      final attributes = img.attributes;
      for (final name in [...lazyAttributes, 'src']) {
        final value = attributes[name]?.trim();
        if (value == null || value.isEmpty) continue;
        final resolved = _resolveImageUrl(baseUrl, value);
        if (resolved != null) return resolved;
      }
    }

    // Pass 2: cover links like <a class="cover lazy" data-bg="…"> — sites
    // (e.g. DM84) render posters as non-<img> elements whose background
    // image URL lives in a data attribute.
    // Walk the node subtree directly so this works regardless of which
    // attribute-selector syntaxes the XPath library supports.
    final htmlNode = node.node;
    if (htmlNode is Element) {
      final found = _findLazyImageAttribute(htmlNode, lazyAttributes);
      if (found != null) {
        final resolved = _resolveImageUrl(baseUrl, found);
        if (resolved != null) return resolved;
      }
    }
    return null;
  }

  /// Depth-first search of [element] and its descendants for the first
  /// non-empty lazy-loading image attribute from [attributeNames].
  String? _findLazyImageAttribute(
    Element element,
    List<String> attributeNames,
  ) {
    for (final name in attributeNames) {
      final value = element.attributes[name]?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    for (final child in element.children) {
      final found = _findLazyImageAttribute(child, attributeNames);
      if (found != null) return found;
    }
    return null;
  }

  String? _resolveImageUrl(String baseUrl, String raw) {
    final value = raw.trim();
    if (value.isEmpty || value.startsWith('data:')) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (value.startsWith('//')) return 'https:$value';
    final base = Uri.tryParse(baseUrl);
    if (base == null || !base.hasScheme) return null;
    try {
      return base.resolve(value).toString();
    } catch (_) {
      return null;
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
