import 'package:kazumi/modules/media/media_item.dart';
import 'package:kazumi/modules/media/media_detail.dart';
import 'package:kazumi/modules/media/media_rule.dart';
import 'package:kazumi/plugins/api_rule_config.dart';
import 'package:kazumi/plugins/anti_crawler_config.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';

/// Exceptions re-exported for convenience (same types as existing engine).
export 'package:kazumi/services/plugin/rule_engine_models.dart'
    show
        CaptchaRequiredException,
        NoResultException,
        SearchErrorException,
        ChapterErrorException,
        RuleCancelToken;

/// Runtime configuration snapshot built from a [MediaRule], compatible with
/// the existing [RuleExecutionConfig] so the proven strategies can be reused.
///
/// This avoids duplicating the engine internals while letting the new
/// universal layer accept [MediaRule] instead of [Plugin].
class MediaRuleExecutionConfig {
  final String ruleName;
  final String baseUrl;
  final bool usePost;
  final String searchMode;
  final String chapterMode;
  final String searchUrl;
  final String searchList;
  final String searchName;
  final String searchResult;
  final String chapterRoads;
  final String chapterResult;
  final ApiSearchConfig searchApiConfig;
  final ApiChapterConfig chapterApiConfig;
  final AntiCrawlerConfig antiCrawlerConfig;

  /// New v9 fields (optional, used when the rule provides them):
  final String? searchCoverXPath;
  final String? searchDescriptionXPath;
  final String? searchYearXPath;

  /// Detail page XPath fields (optional):
  final String? detailCoverXPath;
  final String? detailDescriptionXPath;
  final String? detailYearXPath;
  final String? detailGenreXPath;

  /// Stream resolution config:
  final String streamMode; // "xpath" or "webview"
  final String? streamUrlXPath;
  final bool streamUseLegacyParser;

  /// Home-page recommendations config (optional):
  final String homeUrl; // '' → use baseUrl
  final String homeListXPath;
  final String homeNameXPath;
  final String homeResultXPath;
  final String? homeCoverXPath;

  const MediaRuleExecutionConfig({
    required this.ruleName,
    required this.baseUrl,
    required this.usePost,
    required this.searchMode,
    required this.chapterMode,
    required this.searchUrl,
    required this.searchList,
    required this.searchName,
    required this.searchResult,
    required this.chapterRoads,
    required this.chapterResult,
    required this.searchApiConfig,
    required this.chapterApiConfig,
    required this.antiCrawlerConfig,
    this.searchCoverXPath,
    this.searchDescriptionXPath,
    this.searchYearXPath,
    this.detailCoverXPath,
    this.detailDescriptionXPath,
    this.detailYearXPath,
    this.detailGenreXPath,
    this.streamMode = 'webview',
    this.streamUrlXPath,
    this.streamUseLegacyParser = false,
    this.homeUrl = '',
    this.homeListXPath = '',
    this.homeNameXPath = '',
    this.homeResultXPath = '',
    this.homeCoverXPath,
  });

  /// Whether the rule carries a usable home-recommendation configuration.
  bool get hasHomeConfig =>
      homeListXPath.trim().isNotEmpty &&
      homeNameXPath.trim().isNotEmpty &&
      homeResultXPath.trim().isNotEmpty;

  /// Build from a [MediaRule], extracting legacy fields and new v9 fields.
  factory MediaRuleExecutionConfig.fromRule(MediaRule rule) {
    final search = rule.search;
    final episodes = rule.episodes;
    final stream = rule.stream;
    final antiCrawler = rule.antiCrawler ?? AntiCrawlerConfig.empty();

    // Determine search mode: prefer new section, fall back to legacy field.
    final searchMode = search?.mode ?? rule.searchMode ?? RuleMode.xpath;

    // Determine search URL: prefer new section, fall back to legacy field.
    final searchUrl = search?.url ?? rule.searchURL ?? '';

    // Determine search XPath fields:
    // For v9 rules, extract from structured itemXPath.
    // For legacy rules, use flat fields.
    final searchList = search?.itemXPath?.itemXPath ??
        rule.searchList ??
        '';
    final searchName = search?.itemXPath?.titleXPath ??
        rule.searchName ??
        '';
    final searchResult = search?.itemXPath?.detailUrlXPath ??
        rule.searchResult ??
        '';

    // New v9 search fields:
    final searchCoverXPath = search?.itemXPath?.coverXPath;
    final searchDescriptionXPath = search?.itemXPath?.descriptionXPath;
    final searchYearXPath = search?.itemXPath?.yearXPath;

    // Determine chapter mode:
    final chapterMode = episodes?.mode ?? rule.chapterMode ?? RuleMode.xpath;

    // Determine chapter XPath fields:
    final chapterRoads = episodes?.groupXPath ?? rule.chapterRoads ?? '';
    final chapterResult =
        episodes?.itemXPath?.itemXPath ?? rule.chapterResult ?? '';

    // API configs:
    final searchApiConfig = search?.apiConfig ??
        rule.searchApiConfig ??
        ApiSearchConfig();
    final chapterApiConfig = episodes?.apiConfig ??
        rule.chapterApiConfig ??
        ApiChapterConfig();

    // Use POST if legacy usePost is true or new search method is POST
    final usePost = rule.usePost ||
        (search?.method.toUpperCase() == 'POST');

    // Stream resolution:
    final streamMode = stream?.mode ?? 'webview';
    final streamUrlXPath = stream?.urlXPath;
    final streamUseLegacyParser = rule.useLegacyParser ||
        (stream?.useLegacyParser ?? false);

    // Detail page XPath:
    final detail = rule.detail;

    // Home-page recommendations:
    final home = rule.home;

    return MediaRuleExecutionConfig(
      ruleName: rule.name,
      baseUrl: rule.baseUrl ?? '',
      usePost: usePost,
      searchMode: searchMode,
      chapterMode: chapterMode,
      searchUrl: searchUrl,
      searchList: searchList,
      searchName: searchName,
      searchResult: searchResult,
      chapterRoads: chapterRoads,
      chapterResult: chapterResult,
      searchApiConfig: searchApiConfig,
      chapterApiConfig: chapterApiConfig,
      antiCrawlerConfig: antiCrawler,
      searchCoverXPath: searchCoverXPath,
      searchDescriptionXPath: searchDescriptionXPath,
      searchYearXPath: searchYearXPath,
      detailCoverXPath: detail?.coverXPath,
      detailDescriptionXPath: detail?.descriptionXPath,
      detailYearXPath: detail?.yearXPath,
      detailGenreXPath: detail?.genreXPath,
      streamMode: streamMode,
      streamUrlXPath: streamUrlXPath,
      streamUseLegacyParser: streamUseLegacyParser,
      homeUrl: home?.url ?? '',
      homeListXPath: home?.itemXPath?.itemXPath ?? '',
      homeNameXPath: home?.itemXPath?.titleXPath ?? '',
      homeResultXPath: home?.itemXPath?.detailUrlXPath ?? '',
      homeCoverXPath: home?.itemXPath?.coverXPath,
    );
  }

  /// Convert to the existing [RuleExecutionConfig] for reuse with the
  /// proven [RuleEngine] strategies.
  RuleExecutionConfig toLegacyConfig() {
    return RuleExecutionConfig(
      pluginName: ruleName,
      baseUrl: baseUrl,
      usePost: usePost,
      searchMode: searchMode,
      chapterMode: chapterMode,
      searchUrl: searchUrl,
      searchList: searchList,
      searchName: searchName,
      searchResult: searchResult,
      chapterRoads: chapterRoads,
      chapterResult: chapterResult,
      searchApiConfig: searchApiConfig,
      chapterApiConfig: chapterApiConfig,
      antiCrawlerConfig: antiCrawlerConfig,
    );
  }
}

/// Search result enriched with [MediaItem] instead of plain [SearchItem].
class MediaSearchResult {
  final List<MediaItem> items;
  final List<String> diagnostics;
  final String rawResponse;

  const MediaSearchResult({
    required this.items,
    required this.diagnostics,
    required this.rawResponse,
  });
}

/// Episode/chapter result enriched with [MediaEpisodeGroup].
class MediaEpisodeResult {
  final List<MediaEpisodeGroup> groups;
  final List<String> diagnostics;
  final String rawResponse;

  const MediaEpisodeResult({
    required this.groups,
    required this.diagnostics,
    required this.rawResponse,
  });
}
