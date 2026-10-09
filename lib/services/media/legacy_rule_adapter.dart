import 'package:kazumi/modules/media/media_rule.dart';
import 'package:kazumi/modules/media/media_type.dart';
import 'package:kazumi/plugins/anti_crawler_config.dart';
import 'package:kazumi/plugins/api_rule_config.dart';
import 'package:kazumi/plugins/home_config.dart';
import 'package:kazumi/plugins/plugins.dart';

/// Adapts legacy Kazumi rules (v8 [Plugin]) to the universal [MediaRule]
/// (v9 schema) and vice versa.
///
/// The adapter populates both the new structured sections ([RuleSearch],
/// [RuleEpisodes], [RuleStream], etc.) and the legacy fields on [MediaRule],
/// so that the new engine can prefer the new sections while the old engine
/// can still read the legacy fields.
///
/// Existing rule JSON files and `plugins.json` storage are not modified.
class LegacyRuleAdapter {
  LegacyRuleAdapter._();

  /// Convert a legacy [Plugin] to a [MediaRule].
  static MediaRule fromPlugin(Plugin plugin) {
    final mode = MediaType.fromString(plugin.type);

    return MediaRule(
      version: '9',
      id: pluginNameKey(plugin.name),
      name: plugin.name,
      baseUrl: plugin.baseUrl,
      type: mode == MediaType.unknown && plugin.type == 'anime'
          ? MediaType.anime
          : mode,
      search: _adaptSearch(plugin),
      episodes: _adaptEpisodes(plugin),
      stream: _adaptStream(plugin),
      home: _adaptHome(plugin),
      headers: RuleHeaders(
        userAgent: plugin.userAgent.isEmpty ? null : plugin.userAgent,
        referer: plugin.referer.isEmpty ? null : plugin.referer,
      ),
      antiCrawler: plugin.antiCrawlerConfig.enabled
          ? plugin.antiCrawlerConfig
          : null,
      player: RulePlayer(
        userAgent: plugin.userAgent.isEmpty ? null : plugin.userAgent,
        referer: plugin.referer.isEmpty ? null : plugin.referer,
        adBlocker: plugin.adBlocker,
      ),
      // Legacy fields preserved for backward compatibility
      usePost: plugin.usePost,
      useLegacyParser: plugin.useLegacyParser,
      adBlocker: plugin.adBlocker,
      userAgent: plugin.userAgent.isEmpty ? null : plugin.userAgent,
      referer: plugin.referer.isEmpty ? null : plugin.referer,
      searchURL: plugin.searchURL,
      searchList: plugin.searchList,
      searchName: plugin.searchName,
      searchResult: plugin.searchResult,
      chapterRoads: plugin.chapterRoads,
      chapterResult: plugin.chapterResult,
      searchMode: plugin.searchMode,
      chapterMode: plugin.chapterMode,
      searchApiConfig: plugin.searchApiConfig,
      chapterApiConfig: plugin.chapterApiConfig,
      muliSources: plugin.muliSources,
      useWebview: plugin.useWebview,
      useNativePlayer: plugin.useNativePlayer,
    );
  }

  /// Convert a [MediaRule] back to a legacy [Plugin].
  ///
  /// This is used when serializing to the existing `plugins.json` format
  /// so that older app versions can still read the rule.
  static Plugin toPlugin(MediaRule rule) {
    final searchConfig = rule.searchApiConfig ??
        rule.search?.apiConfig ??
        ApiSearchConfig();
    final chapterConfig = rule.chapterApiConfig ??
        rule.episodes?.apiConfig ??
        ApiChapterConfig();
    final antiCrawler = rule.antiCrawler ?? AntiCrawlerConfig.empty();

    final searchMode = rule.searchMode ??
        rule.search?.mode ??
        RuleMode.xpath;
    final chapterMode = rule.chapterMode ??
        rule.episodes?.mode ??
        RuleMode.xpath;

    return Plugin(
      api: rule.version == '9' ? '8' : rule.version,
      type: rule.type == MediaType.unknown ? 'anime' : rule.type.name,
      name: rule.name,
      version: '',
      muliSources: rule.muliSources ?? true,
      useWebview: rule.useWebview ?? true,
      useNativePlayer: rule.useNativePlayer ?? true,
      usePost: rule.usePost ||
          (rule.search?.method.toUpperCase() == 'POST'),
      useLegacyParser: rule.useLegacyParser ||
          (rule.stream?.useLegacyParser ?? false),
      adBlocker: rule.adBlocker || (rule.player?.adBlocker ?? false),
      userAgent: rule.userAgent ?? rule.player?.userAgent ?? '',
      baseUrl: rule.baseUrl ?? '',
      searchURL: rule.searchURL ?? rule.search?.url ?? '',
      searchList: rule.searchList ?? rule.search?.itemXPath?.itemXPath ?? '',
      searchName: rule.searchName ?? rule.search?.itemXPath?.titleXPath ?? '',
      searchResult:
          rule.searchResult ?? rule.search?.itemXPath?.detailUrlXPath ?? '',
      chapterRoads: rule.chapterRoads ?? rule.episodes?.groupXPath ?? '',
      chapterResult:
          rule.chapterResult ?? rule.episodes?.itemXPath?.itemXPath ?? '',
      referer: rule.referer ?? rule.player?.referer ?? '',
      searchMode: searchMode,
      chapterMode: chapterMode,
      searchApiConfig: searchConfig,
      chapterApiConfig: chapterConfig,
      antiCrawlerConfig: antiCrawler,
      homeConfig: HomeConfig(
        url: rule.home?.url ?? '',
        homeList: rule.home?.itemXPath?.itemXPath ?? '',
        homeName: rule.home?.itemXPath?.titleXPath ?? '',
        homeResult: rule.home?.itemXPath?.detailUrlXPath ?? '',
        homeCover: rule.home?.itemXPath?.coverXPath ?? '',
      ),
    );
  }

  static RuleSearch _adaptSearch(Plugin plugin) {
    if (plugin.usesApiSearch) {
      return RuleSearch(
        mode: RuleMode.api,
        method: plugin.searchApiConfig.request.method,
        url: plugin.searchApiConfig.request.url,
        apiConfig: plugin.searchApiConfig,
      );
    }

    return RuleSearch(
      mode: RuleMode.xpath,
      method: plugin.usePost ? 'POST' : 'GET',
      url: plugin.searchURL,
      itemXPath: RuleSearchItemXPath(
        itemXPath: plugin.searchList,
        titleXPath: plugin.searchName.isNotEmpty ? plugin.searchName : null,
        detailUrlXPath:
            plugin.searchResult.isNotEmpty ? plugin.searchResult : null,
      ),
    );
  }

  static RuleEpisodes _adaptEpisodes(Plugin plugin) {
    if (plugin.chapterMode == RuleMode.api) {
      return RuleEpisodes(
        mode: RuleMode.api,
        url: '{detail_url}',
        apiConfig: plugin.chapterApiConfig,
      );
    }

    return RuleEpisodes(
      mode: RuleMode.xpath,
      url: '{detail_url}',
      groupXPath:
          plugin.chapterRoads.isNotEmpty ? plugin.chapterRoads : null,
      itemXPath: RuleEpisodesItemXPath(
        itemXPath: plugin.chapterResult,
        urlXPath: null, // Legacy XPath reads href from the matched <a> element
      ),
    );
  }

  static RuleStream _adaptStream(Plugin plugin) {
    return RuleStream(
      mode: 'webview',
      url: '{episode_url}',
      useLegacyParser: plugin.useLegacyParser,
    );
  }

  static RuleHome? _adaptHome(Plugin plugin) {
    if (!plugin.homeConfig.isConfigured) return null;
    return RuleHome(
      mode: RuleMode.xpath,
      url: plugin.homeConfig.url,
      itemXPath: RuleSearchItemXPath(
        itemXPath: plugin.homeConfig.homeList,
        titleXPath:
            plugin.homeConfig.homeName.isNotEmpty ? plugin.homeConfig.homeName : null,
        detailUrlXPath: plugin.homeConfig.homeResult.isNotEmpty
            ? plugin.homeConfig.homeResult
            : null,
        coverXPath:
            plugin.homeConfig.homeCover.isNotEmpty ? plugin.homeConfig.homeCover : null,
      ),
    );
  }
}
