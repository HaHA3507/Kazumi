import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:kazumi/modules/media/media_detail.dart';
import 'package:kazumi/modules/media/media_item.dart';
import 'package:kazumi/modules/media/media_rule.dart';
import 'package:kazumi/plugins/api_rule_config.dart';
import 'package:kazumi/services/media/media_rule_models.dart';
import 'package:kazumi/services/plugin/rule_engine.dart' as legacy;
import 'package:kazumi/services/plugin/rule_engine_models.dart';
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

    // Enrich with cover/description/year from v9 XPath fields, then fall
    // back to heuristic poster extraction for items still lacking a cover.
    if (items.isNotEmpty && config.searchMode == RuleMode.xpath) {
      _enrichItems(
        items,
        trace.rawResponse,
        listXPath: config.searchList,
        nameXPath: config.searchName,
        resultXPath: config.searchResult,
        coverXPath: config.searchCoverXPath,
        descriptionXPath: config.searchDescriptionXPath,
        yearXPath: config.searchYearXPath,
        baseUrl: config.baseUrl,
      );
    }

    return MediaSearchResult(
      items: items,
      diagnostics: trace.diagnostics,
      rawResponse: trace.rawResponse,
    );
  }

  /// Queries the source's home page for recommended items.
  ///
  /// Requires the rule to carry home-recommendation XPath fields; throws
  /// [StateError] when the rule has none, so callers can skip such rules.
  /// Reuses the proven legacy search pipeline (HTTP fetch, captcha
  /// detection, XPath item parsing) with the home URL and home XPaths
  /// substituted for the search ones — the empty keyword never appears in
  /// a home URL template, so it is simply not substituted.
  Future<MediaSearchResult> queryHome(
    MediaRule rule, {
    CancelToken? cancelToken,
  }) async {
    final config = MediaRuleExecutionConfig.fromRule(rule);
    if (!config.hasHomeConfig) {
      throw StateError(
        'Rule ${rule.id} has no home recommendation configuration',
      );
    }
    final homeUrl = config.homeUrl.trim().isNotEmpty
        ? config.homeUrl.trim()
        : config.baseUrl;
    if (homeUrl.trim().isEmpty) {
      throw StateError(
        'Rule ${rule.id} has neither a home URL nor a base URL',
      );
    }

    final homeLegacyConfig = RuleExecutionConfig(
      pluginName: config.ruleName,
      baseUrl: config.baseUrl,
      usePost: false,
      searchMode: RuleMode.xpath,
      chapterMode: RuleMode.xpath,
      searchUrl: homeUrl,
      searchList: config.homeListXPath,
      searchName: config.homeNameXPath,
      searchResult: config.homeResultXPath,
      // Chapter fields are never read on this path; mirror the home
      // selectors so no field is left empty.
      chapterRoads: config.homeListXPath,
      chapterResult: config.homeResultXPath,
      searchApiConfig: ApiSearchConfig(),
      chapterApiConfig: ApiChapterConfig(),
      antiCrawlerConfig: config.antiCrawlerConfig,
    );

    final trace = await _legacy.search(
      homeLegacyConfig,
      '',
      cancelToken: cancelToken,
    );

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

    if (items.isNotEmpty) {
      _enrichItems(
        items,
        trace.rawResponse,
        listXPath: config.homeListXPath,
        nameXPath: config.homeNameXPath,
        resultXPath: config.homeResultXPath,
        coverXPath: config.homeCoverXPath,
        baseUrl: config.baseUrl,
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

  /// Enriches [items] with cover/description/year extracted from the
  /// response HTML, walking the [listXPath] nodes in lockstep with the
  /// legacy parser (it skips nodes lacking a name or href, so the item
  /// cursor only advances on nodes that actually produced an item).
  ///
  /// Covers use [coverXPath] when provided; items still lacking a cover
  /// get the heuristic poster extraction (first <img>, then any element
  /// carrying a lazy-loading data-* attribute).
  void _enrichItems(
    List<MediaItem> items,
    String rawHtml, {
    required String listXPath,
    required String nameXPath,
    required String resultXPath,
    String? coverXPath,
    String? descriptionXPath,
    String? yearXPath,
    required String baseUrl,
  }) {
    final list = listXPath.trim();
    if (list.isEmpty) return;
    List<XPathNode<Node>> nodes;
    try {
      final root = _documentElement(rawHtml);
      nodes = root.queryXPath(list).nodes;
    } catch (_) {
      return;
    }

    var itemIndex = 0;
    for (final node in nodes) {
      if (itemIndex >= items.length) break;
      if (!_nodeProducesItem(node, nameXPath, resultXPath)) continue;
      var item = items[itemIndex];
      itemIndex++;

      final coverPath = coverXPath?.trim() ?? '';
      if (coverPath.isNotEmpty) {
        final cover = _extractFromXPathNode(node, coverPath);
        if (cover != null) {
          // Sites may store relative cover URLs; resolve them like the
          // heuristic path does (absolute URLs pass through unchanged).
          final resolved = _resolveImageUrl(baseUrl, cover) ?? cover;
          item = item.copyWith(cover: resolved);
        }
      }
      if (item.cover == null || item.cover!.isEmpty) {
        final heuristic = _firstImageInNode(node, baseUrl);
        if (heuristic != null) item = item.copyWith(cover: heuristic);
      }
      final descPath = descriptionXPath?.trim() ?? '';
      if (descPath.isNotEmpty) {
        final desc = _extractFromXPathNode(node, descPath);
        if (desc != null) item = item.copyWith(description: desc);
      }
      final yearPath = yearXPath?.trim() ?? '';
      if (yearPath.isNotEmpty) {
        final year = _extractFromXPathNode(node, yearPath);
        if (year != null) item = item.copyWith(year: year);
      }
      items[itemIndex - 1] = item;
    }
  }

  /// Mirrors the legacy parser's validity check so the node-to-item cursor
  /// stays aligned when the parser skipped nodes.
  bool _nodeProducesItem(
    XPathNode<Node> node,
    String nameXPath,
    String resultXPath,
  ) {
    try {
      final name = node.queryXPath(nameXPath).node?.text?.trim() ?? '';
      final href =
          node.queryXPath(resultXPath).node?.attributes['href']?.trim() ?? '';
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
    final trimmed = xpath.trim();

    // Attribute query (`…/@attr`): select the element part and read the
    // named attribute. The XPath library returns the element for such
    // queries, so attributes.values.first would pick whatever attribute
    // happens to come first — href on a cover anchor, not its data-bg.
    final attrQuery = _splitAttributeXPath(trimmed);
    if (attrQuery != null) {
      final (elementPath, attrName) = attrQuery;
      try {
        if (elementPath.isEmpty || elementPath == '.') {
          return _nonEmpty(root.attributes[attrName]?.trim());
        }
        for (final element in root.queryXPath(elementPath).nodes) {
          final value = _nonEmpty(element.attributes[attrName]?.trim());
          if (value != null) return value;
        }
        return null;
      } catch (_) {
        return null;
      }
    }

    try {
      final node = root.queryXPath(trimmed).node;
      if (node == null) return null;
      final text = node.text?.trim();
      if (text != null && text.isNotEmpty) return text;
      final attrs = node.attributes.values;
      return attrs.isNotEmpty ? attrs.first.trim() : null;
    } catch (_) {
      return null;
    }
  }

  String? _extractFromXPathNode(XPathNode<Node> parent, String xpath) {
    if (xpath.trim().isEmpty) return null;
    final trimmed = xpath.trim();

    final attrQuery = _splitAttributeXPath(trimmed);
    if (attrQuery != null) {
      final (elementPath, attrName) = attrQuery;
      try {
        final elements = elementPath.isEmpty || elementPath == '.'
            ? <XPathNode<Node>>[parent]
            : parent.queryXPath(elementPath).nodes;
        for (final element in elements) {
          final value = _nonEmpty(element.attributes[attrName]?.trim());
          if (value != null) return value;
        }
        return null;
      } catch (_) {
        return null;
      }
    }

    try {
      final node = parent.queryXPath(trimmed).node;
      if (node == null) return null;
      final text = node.text?.trim();
      if (text != null && text.isNotEmpty) return text;
      final attrs = node.attributes.values;
      return attrs.isNotEmpty ? attrs.first.trim() : null;
    } catch (_) {
      return null;
    }
  }

  /// Splits an XPath ending in an explicit attribute step (`…/@attr`) into
  /// the element path and the attribute name.
  ///
  /// Returns null for element/text queries (`…/a`, `…/p/text()`), which
  /// keep their existing extraction semantics.
  (String, String)? _splitAttributeXPath(String xpath) {
    final match = RegExp(r'/@([A-Za-z_][\w:.-]*)$').firstMatch(xpath);
    if (match == null) return null;
    return (xpath.substring(0, match.start), match.group(1)!);
  }

  static String? _nonEmpty(String? value) =>
      value != null && value.isNotEmpty ? value : null;
}
