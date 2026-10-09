import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/media/media_rule.dart';
import 'package:kazumi/modules/media/media_type.dart';
import 'package:kazumi/plugins/anti_crawler_config.dart';
import 'package:kazumi/plugins/api_rule_config.dart';
import 'package:kazumi/plugins/home_config.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/media/legacy_rule_adapter.dart';

void main() {
  group('LegacyRuleAdapter', () {
    test('fromPlugin converts XPath rule to MediaRule', () {
      final plugin = Plugin(
        api: '8',
        type: 'anime',
        name: 'TestRule',
        version: '1.0',
        muliSources: true,
        useWebview: true,
        useNativePlayer: true,
        usePost: false,
        useLegacyParser: false,
        adBlocker: true,
        userAgent: 'TestUA/1.0',
        baseUrl: 'https://example.com/',
        searchURL: 'https://example.com/search?q=@keyword',
        searchList: '//div[@class="item"]',
        searchName: './/h3/text()',
        searchResult: './/a/@href',
        chapterRoads: '//div[@class="road"]',
        chapterResult: './/a',
        referer: 'https://example.com/',
      );

      final rule = LegacyRuleAdapter.fromPlugin(plugin);

      expect(rule.version, '9');
      expect(rule.id, 'testrule');
      expect(rule.name, 'TestRule');
      expect(rule.baseUrl, 'https://example.com/');
      expect(rule.type, MediaType.anime);

      // Search section
      expect(rule.search, isNotNull);
      expect(rule.search!.mode, RuleMode.xpath);
      expect(rule.search!.method, 'GET');
      expect(rule.search!.url, 'https://example.com/search?q=@keyword');
      expect(rule.search!.itemXPath?.itemXPath, '//div[@class="item"]');
      expect(rule.search!.itemXPath?.titleXPath, './/h3/text()');
      expect(rule.search!.itemXPath?.detailUrlXPath, './/a/@href');

      // Episodes section
      expect(rule.episodes, isNotNull);
      expect(rule.episodes!.mode, RuleMode.xpath);
      expect(rule.episodes!.url, '{detail_url}');
      expect(rule.episodes!.groupXPath, '//div[@class="road"]');
      expect(rule.episodes!.itemXPath?.itemXPath, './/a');

      // Stream section
      expect(rule.stream, isNotNull);
      expect(rule.stream!.mode, 'webview');
      expect(rule.stream!.url, '{episode_url}');

      // Player section
      expect(rule.player?.userAgent, 'TestUA/1.0');
      expect(rule.player?.referer, 'https://example.com/');
      expect(rule.player?.adBlocker, isTrue);

      // Legacy fields preserved
      expect(rule.usePost, isFalse);
      expect(rule.adBlocker, isTrue);
      expect(rule.searchURL, 'https://example.com/search?q=@keyword');
      expect(rule.searchList, '//div[@class="item"]');
    });

    test('fromPlugin converts API mode rule', () {
      final plugin = Plugin(
        api: '8',
        type: 'anime',
        name: 'ApiRule',
        version: '1.0',
        muliSources: true,
        useWebview: true,
        useNativePlayer: true,
        usePost: false,
        useLegacyParser: false,
        adBlocker: false,
        userAgent: '',
        baseUrl: 'https://api.example.com/',
        searchURL: '',
        searchList: '',
        searchName: '',
        searchResult: '',
        chapterRoads: '',
        chapterResult: '',
        referer: '',
        searchMode: RuleMode.api,
        chapterMode: RuleMode.api,
        searchApiConfig: ApiSearchConfig(
          request: ApiRequestConfig(method: 'GET', url: 'https://api.example.com/search'),
          listPath: r'$.data[*]',
          namePath: r'$.title',
          sourcePath: r'$.url',
        ),
        chapterApiConfig: ApiChapterConfig(
          request: ApiRequestConfig(method: 'GET', url: 'https://api.example.com/episodes'),
        ),
      );

      final rule = LegacyRuleAdapter.fromPlugin(plugin);

      expect(rule.search!.mode, RuleMode.api);
      expect(rule.search!.apiConfig, isNotNull);
      expect(rule.search!.apiConfig!.listPath, r'$.data[*]');
      expect(rule.search!.apiConfig!.namePath, r'$.title');

      expect(rule.episodes!.mode, RuleMode.api);
      expect(rule.episodes!.apiConfig, isNotNull);
    });

    test('fromPlugin handles non-anime type', () {
      final plugin = Plugin(
        api: '8',
        type: 'tv',
        name: 'TVRule',
        version: '1.0',
        muliSources: true,
        useWebview: true,
        useNativePlayer: true,
        usePost: false,
        useLegacyParser: false,
        adBlocker: false,
        userAgent: '',
        baseUrl: '',
        searchURL: '',
        searchList: '',
        searchName: '',
        searchResult: '',
        chapterRoads: '',
        chapterResult: '',
        referer: '',
      );

      final rule = LegacyRuleAdapter.fromPlugin(plugin);

      expect(rule.type, MediaType.tv);
    });

    test('fromPlugin preserves antiCrawler when enabled', () {
      final plugin = Plugin(
        api: '8',
        type: 'anime',
        name: 'CaptchaRule',
        version: '1.0',
        muliSources: true,
        useWebview: true,
        useNativePlayer: true,
        usePost: false,
        useLegacyParser: false,
        adBlocker: false,
        userAgent: '',
        baseUrl: '',
        searchURL: '',
        searchList: '',
        searchName: '',
        searchResult: '',
        chapterRoads: '',
        chapterResult: '',
        referer: '',
        antiCrawlerConfig: AntiCrawlerConfig(
          enabled: true,
          captchaType: CaptchaType.imageCaptcha,
          captchaImage: '//img[@id="captcha"]',
          captchaInput: '//input[@id="code"]',
          captchaButton: '//button[@id="submit"]',
        ),
      );

      final rule = LegacyRuleAdapter.fromPlugin(plugin);

      expect(rule.antiCrawler, isNotNull);
      expect(rule.antiCrawler!.enabled, isTrue);
      expect(rule.antiCrawler!.captchaType, CaptchaType.imageCaptcha);
      expect(rule.antiCrawler!.captchaImage, '//img[@id="captcha"]');
    });

    test('fromPlugin maps homeConfig to RuleHome', () {
      final plugin = Plugin(
        api: '8',
        type: 'anime',
        name: 'HomeRule',
        version: '1.0',
        muliSources: true,
        useWebview: true,
        useNativePlayer: true,
        usePost: false,
        useLegacyParser: false,
        adBlocker: false,
        userAgent: '',
        baseUrl: 'https://example.com/',
        searchURL: '',
        searchList: '',
        searchName: '',
        searchResult: '',
        chapterRoads: '',
        chapterResult: '',
        referer: '',
        homeConfig: HomeConfig(
          url: 'https://example.com/hot.html',
          homeList: '//div[@class="hot"]/a',
          homeName: './span',
          homeResult: './@href',
          homeCover: './img/@src',
        ),
      );

      final rule = LegacyRuleAdapter.fromPlugin(plugin);

      expect(rule.home, isNotNull);
      expect(rule.home!.mode, RuleMode.xpath);
      expect(rule.home!.url, 'https://example.com/hot.html');
      expect(rule.home!.itemXPath?.itemXPath, '//div[@class="hot"]/a');
      expect(rule.home!.itemXPath?.titleXPath, './span');
      expect(rule.home!.itemXPath?.detailUrlXPath, './@href');
      expect(rule.home!.itemXPath?.coverXPath, './img/@src');

      // Round-trip back to a Plugin keeps the home config.
      final restored = LegacyRuleAdapter.toPlugin(rule);
      expect(restored.homeConfig.isConfigured, isTrue);
      expect(restored.homeConfig.url, 'https://example.com/hot.html');
      expect(restored.homeConfig.homeList, '//div[@class="hot"]/a');
      expect(restored.homeConfig.homeName, './span');
      expect(restored.homeConfig.homeResult, './@href');
      expect(restored.homeConfig.homeCover, './img/@src');
    });

    test('fromPlugin leaves home null without homeConfig', () {
      final plugin = Plugin.fromTemplate()..name = 'NoHome';

      final rule = LegacyRuleAdapter.fromPlugin(plugin);

      expect(rule.home, isNull);
    });

    test('Plugin serializes homeConfig only when configured', () {
      final configured = Plugin.fromTemplate()
        ..name = 'WithHome'
        ..homeConfig = HomeConfig(
          url: 'https://example.com/hot.html',
          homeList: '//a',
          homeName: './span',
          homeResult: './@href',
        );

      final json = configured.toJson();
      expect(json['homeConfig'], isNotNull);
      final restored = Plugin.fromJson(json);
      expect(restored.homeConfig.isConfigured, isTrue);
      expect(restored.homeConfig.homeList, '//a');

      // Unconfigured home stays out of the persisted JSON.
      final bare = Plugin.fromTemplate()..name = 'NoHome';
      expect(bare.toJson().containsKey('homeConfig'), isFalse);
      expect(bare.homeConfig.isConfigured, isFalse);
    });

    test('fromPlugin sets antiCrawler to null when disabled', () {
      final plugin = Plugin.fromTemplate()..name = 'NoCaptcha';

      final rule = LegacyRuleAdapter.fromPlugin(plugin);

      expect(rule.antiCrawler, isNull);
    });

    test('toPlugin round-trips a simple XPath rule', () {
      final original = Plugin(
        api: '8',
        type: 'anime',
        name: 'RoundTrip',
        version: '2.0',
        muliSources: true,
        useWebview: true,
        useNativePlayer: true,
        usePost: true,
        useLegacyParser: true,
        adBlocker: true,
        userAgent: 'MyUA',
        baseUrl: 'https://example.org/',
        searchURL: 'https://example.org/search?@keyword',
        searchList: '//div',
        searchName: '//h2',
        searchResult: '//a',
        chapterRoads: '//ul',
        chapterResult: '//li',
        referer: 'https://example.org/',
      );

      final rule = LegacyRuleAdapter.fromPlugin(original);
      final restored = LegacyRuleAdapter.toPlugin(rule);

      expect(restored.name, 'RoundTrip');
      expect(restored.type, 'anime');
      expect(restored.baseUrl, 'https://example.org/');
      expect(restored.usePost, isTrue);
      expect(restored.useLegacyParser, isTrue);
      expect(restored.adBlocker, isTrue);
      expect(restored.userAgent, 'MyUA');
      expect(restored.referer, 'https://example.org/');
      expect(restored.searchURL, 'https://example.org/search?@keyword');
      expect(restored.searchList, '//div');
      expect(restored.searchName, '//h2');
      expect(restored.searchResult, '//a');
      expect(restored.chapterRoads, '//ul');
      expect(restored.chapterResult, '//li');
    });

    test('toPlugin converts new v9 rule back to v8 api field', () {
      final rule = MediaRule(
        version: '9',
        id: 'v9rule',
        name: 'V9Rule',
        baseUrl: 'https://v9.example.com/',
        type: MediaType.video,
        search: RuleSearch(
          mode: 'xpath',
          method: 'POST',
          url: 'https://v9.example.com/search',
          itemXPath: RuleSearchItemXPath(
            itemXPath: '//div[@class="result"]',
            titleXPath: './/h3',
            detailUrlXPath: './/a/@href',
          ),
        ),
        episodes: RuleEpisodes(
          mode: 'xpath',
          groupXPath: '//div[@class="line"]',
          itemXPath: RuleEpisodesItemXPath(
            itemXPath: './/a',
          ),
        ),
      );

      final plugin = LegacyRuleAdapter.toPlugin(rule);

      expect(plugin.api, '8');
      expect(plugin.name, 'V9Rule');
      expect(plugin.type, 'video');
      expect(plugin.baseUrl, 'https://v9.example.com/');
      expect(plugin.usePost, isTrue); // because method is POST
      expect(plugin.searchURL, 'https://v9.example.com/search');
      expect(plugin.searchList, '//div[@class="result"]');
      expect(plugin.searchName, './/h3');
      expect(plugin.searchResult, './/a/@href');
      expect(plugin.chapterRoads, '//div[@class="line"]');
      expect(plugin.chapterResult, './/a');
    });
  });
}
