import 'package:kazumi/modules/media/media_type.dart';
import 'package:kazumi/plugins/anti_crawler_config.dart';
import 'package:kazumi/plugins/api_rule_config.dart';

/// Configuration for HTTP headers used by the rule engine and player.
class RuleHeaders {
  /// User-Agent for HTTP requests. When empty, the engine uses a random UA.
  final String? userAgent;

  /// Referer for HTTP requests.
  final String? referer;

  /// Additional custom headers.
  final Map<String, String>? custom;

  RuleHeaders({this.userAgent, this.referer, this.custom});

  factory RuleHeaders.fromJson(Map<String, dynamic> json) {
    return RuleHeaders(
      userAgent: json['user_agent'] as String?,
      referer: json['referer'] as String?,
      custom: json['custom'] is Map
          ? Map<String, String>.from(json['custom'] as Map)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        if (userAgent != null) 'user_agent': userAgent,
        if (referer != null) 'referer': referer,
        if (custom != null) 'custom': custom,
      };
}

/// XPath configuration for extracting a single search result item.
class RuleSearchItemXPath {
  /// XPath selector for the list of search result items.
  final String itemXPath;

  /// XPath (relative to item) for the title.
  final String? titleXPath;

  /// XPath (relative to item) for the cover image URL.
  final String? coverXPath;

  /// XPath (relative to item) for the detail page URL.
  final String? detailUrlXPath;

  /// XPath (relative to item) for the description.
  final String? descriptionXPath;

  /// XPath (relative to item) for the year.
  final String? yearXPath;

  RuleSearchItemXPath({
    required this.itemXPath,
    this.titleXPath,
    this.coverXPath,
    this.detailUrlXPath,
    this.descriptionXPath,
    this.yearXPath,
  });

  factory RuleSearchItemXPath.fromJson(Map<String, dynamic> json) {
    return RuleSearchItemXPath(
      itemXPath: json['xpath'] as String? ?? '',
      titleXPath: json['title'] as String?,
      coverXPath: json['cover'] as String?,
      detailUrlXPath: json['detail_url'] as String?,
      descriptionXPath: json['description'] as String?,
      yearXPath: json['year'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'xpath': itemXPath,
        if (titleXPath != null) 'title': titleXPath,
        if (coverXPath != null) 'cover': coverXPath,
        if (detailUrlXPath != null) 'detail_url': detailUrlXPath,
        if (descriptionXPath != null) 'description': descriptionXPath,
        if (yearXPath != null) 'year': yearXPath,
      };
}

/// Search section of a [MediaRule].
class RuleSearch {
  /// Parsing mode: "xpath" or "api".
  final String mode;

  /// HTTP method: "GET" or "POST".
  final String method;

  /// Search URL template. Supports `{keyword}` and `{page}` variables.
  /// Also supports legacy `@keyword` syntax.
  final String url;

  /// XPath item extraction (when mode == "xpath").
  final RuleSearchItemXPath? itemXPath;

  /// API search config (when mode == "api").
  final ApiSearchConfig? apiConfig;

  /// Pagination configuration (optional).
  final RulePagination? pagination;

  RuleSearch({
    this.mode = 'xpath',
    this.method = 'GET',
    this.url = '',
    this.itemXPath,
    this.apiConfig,
    this.pagination,
  });

  factory RuleSearch.fromJson(Map<String, dynamic> json) {
    return RuleSearch(
      mode: RuleMode.normalize(json['mode']),
      method: (json['method'] as String? ?? 'GET').toUpperCase(),
      url: json['url'] as String? ?? '',
      itemXPath: json['item'] is Map
          ? RuleSearchItemXPath.fromJson(Map<String, dynamic>.from(json['item']))
          : null,
      apiConfig: json['api'] is Map
          ? ApiSearchConfig.fromJson(Map<String, dynamic>.from(json['api']))
          : null,
      pagination: json['pagination'] is Map
          ? RulePagination.fromJson(
              Map<String, dynamic>.from(json['pagination']))
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'method': method,
        'url': url,
        if (itemXPath != null) 'item': itemXPath!.toJson(),
        if (apiConfig != null) 'api': apiConfig!.toJson(),
        if (pagination != null) 'pagination': pagination!.toJson(),
      };
}

/// Pagination configuration for search.
class RulePagination {
  /// Starting page number (default 1).
  final int pageStart;

  /// Number of results per page (0 = unknown / not used).
  final int pageSize;

  RulePagination({this.pageStart = 1, this.pageSize = 0});

  factory RulePagination.fromJson(Map<String, dynamic> json) {
    return RulePagination(
      pageStart: json['page_start'] as int? ?? 1,
      pageSize: json['page_size'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'page_start': pageStart,
        if (pageSize > 0) 'page_size': pageSize,
      };
}

/// Detail section of a [MediaRule] (optional).
///
/// When present, the engine fetches the detail page URL and extracts
/// additional metadata not available in search results.
class RuleDetail {
  /// Detail page URL template. Supports `{detail_url}` variable.
  final String url;

  /// XPath for the cover image.
  final String? coverXPath;

  /// XPath for the description.
  final String? descriptionXPath;

  /// XPath for the year.
  final String? yearXPath;

  /// XPath for the genre.
  final String? genreXPath;

  RuleDetail({
    this.url = '{detail_url}',
    this.coverXPath,
    this.descriptionXPath,
    this.yearXPath,
    this.genreXPath,
  });

  factory RuleDetail.fromJson(Map<String, dynamic> json) {
    return RuleDetail(
      url: json['url'] as String? ?? '{detail_url}',
      coverXPath: json['cover'] as String?,
      descriptionXPath: json['description'] as String?,
      yearXPath: json['year'] as String?,
      genreXPath: json['genre'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        if (coverXPath != null) 'cover': coverXPath,
        if (descriptionXPath != null) 'description': descriptionXPath,
        if (yearXPath != null) 'year': yearXPath,
        if (genreXPath != null) 'genre': genreXPath,
      };
}

/// XPath configuration for extracting episode items.
class RuleEpisodesItemXPath {
  /// XPath selector for episode items (relative to the group, or to the
  /// document root when no group is defined).
  final String itemXPath;

  /// XPath (relative to item) for the episode title.
  final String? titleXPath;

  /// XPath (relative to item) for the episode URL.
  final String? urlXPath;

  RuleEpisodesItemXPath({
    required this.itemXPath,
    this.titleXPath,
    this.urlXPath,
  });

  factory RuleEpisodesItemXPath.fromJson(Map<String, dynamic> json) {
    return RuleEpisodesItemXPath(
      itemXPath: json['xpath'] as String? ?? '',
      titleXPath: json['title'] as String?,
      urlXPath: json['url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'xpath': itemXPath,
        if (titleXPath != null) 'title': titleXPath,
        if (urlXPath != null) 'url': urlXPath,
      };
}

/// Episodes section of a [MediaRule].
class RuleEpisodes {
  /// Parsing mode: "xpath" or "api".
  final String mode;

  /// Episodes page URL template. Supports `{detail_url}` and `{source}`.
  final String url;

  /// Group (road) XPath selector (optional). When absent, all episodes
  /// are in a single default group.
  final String? groupXPath;

  /// Group title XPath (relative to the group node).
  final String? groupTitleXPath;

  /// Episode item XPath configuration (when mode == "xpath").
  final RuleEpisodesItemXPath? itemXPath;

  /// API chapter config (when mode == "api").
  final ApiChapterConfig? apiConfig;

  RuleEpisodes({
    this.mode = 'xpath',
    this.url = '{detail_url}',
    this.groupXPath,
    this.groupTitleXPath,
    this.itemXPath,
    this.apiConfig,
  });

  factory RuleEpisodes.fromJson(Map<String, dynamic> json) {
    return RuleEpisodes(
      mode: RuleMode.normalize(json['mode']),
      url: json['url'] as String? ?? '{detail_url}',
      groupXPath: json['group'] is Map
          ? (json['group'] as Map)['xpath'] as String?
          : null,
      groupTitleXPath: json['group'] is Map
          ? (json['group'] as Map)['title'] as String?
          : null,
      itemXPath: json['item'] is Map
          ? RuleEpisodesItemXPath.fromJson(
              Map<String, dynamic>.from(json['item']))
          : null,
      apiConfig: json['api'] is Map
          ? ApiChapterConfig.fromJson(Map<String, dynamic>.from(json['api']))
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'url': url,
        if (groupXPath != null)
          'group': {'xpath': groupXPath, if (groupTitleXPath != null) 'title': groupTitleXPath},
        if (itemXPath != null) 'item': itemXPath!.toJson(),
        if (apiConfig != null) 'api': apiConfig!.toJson(),
      };
}

/// Stream resolution section of a [MediaRule] (optional).
///
/// When present with `mode == "xpath"`, the engine extracts the stream URL
/// directly from the play page HTML. When `mode == "webview"` (default),
/// the engine falls back to WebView-based interception.
class RuleStream {
  /// Resolution mode: "xpath" or "webview".
  final String mode;

  /// Play page URL template. Supports `{episode_url}`.
  final String url;

  /// XPath for the stream URL (when mode == "xpath").
  final String? urlXPath;

  /// Whether to use the legacy iframe-listener parser (when mode == "webview").
  final bool useLegacyParser;

  RuleStream({
    this.mode = 'webview',
    this.url = '{episode_url}',
    this.urlXPath,
    this.useLegacyParser = false,
  });

  factory RuleStream.fromJson(Map<String, dynamic> json) {
    return RuleStream(
      mode: json['mode'] as String? ?? 'webview',
      url: json['url'] as String? ?? '{episode_url}',
      urlXPath: json['url_xpath'] as String?,
      useLegacyParser: json['use_legacy_parser'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'url': url,
        if (urlXPath != null) 'url_xpath': urlXPath,
        if (useLegacyParser) 'use_legacy_parser': useLegacyParser,
      };
}

/// Player configuration section of a [MediaRule].
class RulePlayer {
  /// User-Agent for the media player. When empty, a random UA is used.
  final String? userAgent;

  /// Referer for the media player.
  final String? referer;

  /// Enable HLS ad filtering during playback.
  final bool adBlocker;

  RulePlayer({
    this.userAgent,
    this.referer,
    this.adBlocker = false,
  });

  factory RulePlayer.fromJson(Map<String, dynamic> json) {
    return RulePlayer(
      userAgent: json['user_agent'] as String?,
      referer: json['referer'] as String?,
      adBlocker: json['ad_blocker'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        if (userAgent != null) 'user_agent': userAgent,
        if (referer != null) 'referer': referer,
        if (adBlocker) 'ad_blocker': adBlocker,
      };
}

/// Universal media rule — describes how to search, parse detail, extract
/// episodes and resolve streams from a target website.
///
/// New rules (v9 schema) use the structured [search], [detail], [episodes]
/// and [stream] sections. Legacy rules (v8) are adapted via
/// [LegacyRuleAdapter] which populates both the new sections and the
/// legacy fields below.
class MediaRule {
  /// Schema version (e.g. "9" for new schema, "8" for legacy).
  final String version;

  /// Rule identifier (typically the rule name, lowercased).
  final String id;

  /// Display name.
  final String name;

  /// Base URL of the target website.
  final String? baseUrl;

  /// Content type hint (optional).
  final MediaType type;

  /// Search configuration.
  final RuleSearch? search;

  /// Detail configuration (optional).
  final RuleDetail? detail;

  /// Episodes configuration.
  final RuleEpisodes? episodes;

  /// Stream resolution configuration (optional).
  final RuleStream? stream;

  /// HTTP headers configuration.
  final RuleHeaders? headers;

  /// Anti-crawler / captcha configuration.
  final AntiCrawlerConfig? antiCrawler;

  /// Player configuration.
  final RulePlayer? player;

  // --- Legacy fields (v8 compatibility) ---

  final bool usePost;
  final bool useLegacyParser;
  final bool adBlocker;
  final String? userAgent;
  final String? referer;
  final String? searchURL;
  final String? searchList;
  final String? searchName;
  final String? searchResult;
  final String? chapterRoads;
  final String? chapterResult;
  final String? searchMode;
  final String? chapterMode;
  final ApiSearchConfig? searchApiConfig;
  final ApiChapterConfig? chapterApiConfig;
  final bool? muliSources;
  final bool? useWebview;
  final bool? useNativePlayer;

  MediaRule({
    required this.version,
    required this.id,
    required this.name,
    this.baseUrl,
    this.type = MediaType.unknown,
    this.search,
    this.detail,
    this.episodes,
    this.stream,
    this.headers,
    this.antiCrawler,
    this.player,
    this.usePost = false,
    this.useLegacyParser = false,
    this.adBlocker = false,
    this.userAgent,
    this.referer,
    this.searchURL,
    this.searchList,
    this.searchName,
    this.searchResult,
    this.chapterRoads,
    this.chapterResult,
    this.searchMode,
    this.chapterMode,
    this.searchApiConfig,
    this.chapterApiConfig,
    this.muliSources,
    this.useWebview,
    this.useNativePlayer,
  });

  /// Whether this rule uses the new v9 structured schema.
  bool get isV9 => search != null || episodes != null;

  /// Whether this rule uses the legacy v8 flat schema.
  bool get isLegacy => !isV9;
}
