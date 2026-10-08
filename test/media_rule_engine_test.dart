import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/media/media_rule.dart';
import 'package:kazumi/modules/media/media_type.dart';
import 'package:kazumi/plugins/api_rule_config.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/media/media_rule_engine.dart';
import 'package:kazumi/services/media/media_rule_models.dart';
import 'package:kazumi/services/media/plugin_rule_extension.dart';
import 'package:kazumi/services/plugin/rule_engine.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';

void main() {
  const xpathResponse = '''
<html>
  <article class="result"><h2><a href="/video/alpha">Alpha</a></h2></article>
  <div class="road"><a href="/play/alpha-1">第1集</a><a href="/play/alpha-2">第2集</a></div>
</html>
''';

  final apiSearchFixture = jsonEncode({
    'data': [
      {'name': 'API result', 'id': 'api-id'},
    ],
  });

  final apiChapterFixture = jsonEncode({
    'data': {
      'roads': [
        {
          'name': 'API road',
          'episodes': [
            {'name': 'Episode 1', 'url': '/api-play/1'},
          ],
        },
      ],
    },
  });

  group('MediaRuleExecutionConfig', () {
    test('fromRule maps v9 structured fields', () {
      final rule = MediaRule(
        version: '9',
        id: 'test',
        name: 'Test',
        baseUrl: 'https://example.com/',
        type: MediaType.video,
        search: RuleSearch(
          mode: 'xpath',
          method: 'POST',
          url: 'https://example.com/search?q={keyword}',
          itemXPath: RuleSearchItemXPath(
            itemXPath: '//div[@class="item"]',
            titleXPath: './/h3',
            coverXPath: './/img/@src',
            detailUrlXPath: './/a/@href',
            descriptionXPath: './/p',
            yearXPath: './/span[@class="year"]',
          ),
        ),
        episodes: RuleEpisodes(
          mode: 'xpath',
          groupXPath: '//div[@class="road"]',
          itemXPath: RuleEpisodesItemXPath(
            itemXPath: './/a',
          ),
        ),
        stream: RuleStream(
          mode: 'xpath',
          urlXPath: '//source/@src',
        ),
      );

      final config = MediaRuleExecutionConfig.fromRule(rule);

      expect(config.ruleName, 'Test');
      expect(config.baseUrl, 'https://example.com/');
      expect(config.searchMode, 'xpath');
      expect(config.usePost, isTrue);
      expect(config.searchUrl, 'https://example.com/search?q={keyword}');
      expect(config.searchList, '//div[@class="item"]');
      expect(config.searchName, './/h3');
      expect(config.searchResult, './/a/@href');
      expect(config.searchCoverXPath, './/img/@src');
      expect(config.searchDescriptionXPath, './/p');
      expect(config.searchYearXPath, './/span[@class="year"]');
      expect(config.chapterRoads, '//div[@class="road"]');
      expect(config.chapterResult, './/a');
      expect(config.streamMode, 'xpath');
      expect(config.streamUrlXPath, '//source/@src');
    });

    test('fromRule maps legacy v8 fields', () {
      final plugin = Plugin(
        api: '8',
        type: 'anime',
        name: 'LegacyRule',
        version: '1.0',
        muliSources: true,
        useWebview: true,
        useNativePlayer: true,
        usePost: true,
        useLegacyParser: false,
        adBlocker: false,
        userAgent: '',
        baseUrl: 'https://example.org/',
        searchURL: 'https://example.org/search?q=@keyword',
        searchList: '//div[@class="item"]',
        searchName: '//h3',
        searchResult: '//a',
        chapterRoads: '//ul',
        chapterResult: '//li',
        referer: '',
      );

      final rule = plugin.toMediaRule();
      final config = MediaRuleExecutionConfig.fromRule(rule);

      expect(config.ruleName, 'LegacyRule');
      expect(config.baseUrl, 'https://example.org/');
      expect(config.searchMode, 'xpath');
      expect(config.usePost, isTrue);
      expect(config.searchUrl, 'https://example.org/search?q=@keyword');
      expect(config.searchList, '//div[@class="item"]');
      expect(config.searchName, '//h3');
      expect(config.searchResult, '//a');
      expect(config.chapterRoads, '//ul');
      expect(config.chapterResult, '//li');
      // No v9 fields
      expect(config.searchCoverXPath, isNull);
      expect(config.streamMode, 'webview');
    });

    test('toLegacyConfig produces a valid RuleExecutionConfig', () {
      final rule = MediaRule(
        version: '9',
        id: 'test',
        name: 'Test',
        baseUrl: 'https://example.com/',
        search: RuleSearch(
          mode: 'xpath',
          url: 'https://example.com/search',
          itemXPath: RuleSearchItemXPath(
            itemXPath: '//div',
            titleXPath: './/h3',
            detailUrlXPath: './/a/@href',
          ),
        ),
        episodes: RuleEpisodes(
          mode: 'xpath',
          groupXPath: '//div[@class="road"]',
        ),
      );

      final config = MediaRuleExecutionConfig.fromRule(rule);
      final legacy = config.toLegacyConfig();

      expect(legacy.pluginName, 'Test');
      expect(legacy.baseUrl, 'https://example.com/');
      expect(legacy.searchMode, 'xpath');
      expect(legacy.searchUrl, 'https://example.com/search');
      expect(legacy.searchList, '//div');
      expect(legacy.searchName, './/h3');
      expect(legacy.searchResult, './/a/@href');
      expect(legacy.chapterRoads, '//div[@class="road"]');
    });
  });

  group('MediaRuleEngine', () {
    test('search produces MediaItem[] for XPath rule', () async {
      final executor = _FakeExecutor([xpathResponse]);
      final legacyEngine = RuleEngine(
        requestExecutor: executor,
        logFailures: false,
      );
      final engine = MediaRuleEngine(legacyEngine: legacyEngine);

      final rule = MediaRule(
        version: '9',
        id: 'testrule',
        name: 'TestRule',
        baseUrl: 'https://example.com/',
        type: MediaType.video,
        search: RuleSearch(
          mode: 'xpath',
          url: 'https://example.com/search?q=@keyword',
          itemXPath: RuleSearchItemXPath(
            itemXPath: '//article[@class="result"]',
            titleXPath: './/h2/a',
            detailUrlXPath: './/h2/a/@href',
          ),
        ),
        episodes: RuleEpisodes(
          mode: 'xpath',
          groupXPath: '//div[@class="road"]',
          itemXPath: RuleEpisodesItemXPath(itemXPath: './/a'),
        ),
      );

      final result = await engine.search(rule, 'alpha');

      expect(result.items, hasLength(1));
      expect(result.items.first.title, 'Alpha');
      expect(result.items.first.sourceId, 'testrule');
      expect(result.items.first.type, MediaType.video);
      expect(result.items.first.detailUrl, isNotNull);
      expect(result.items.first.detailUrl, contains('alpha'));
    });

    test('search produces MediaItem[] for API rule', () async {
      final executor = _FakeExecutor([apiSearchFixture]);
      final legacyEngine = RuleEngine(
        requestExecutor: executor,
        logFailures: false,
      );
      final engine = MediaRuleEngine(legacyEngine: legacyEngine);

      final rule = MediaRule(
        version: '9',
        id: 'apirule',
        name: 'ApiRule',
        baseUrl: 'https://example.com/',
        search: RuleSearch(
          mode: 'api',
          apiConfig: ApiSearchConfig(
            request: ApiRequestConfig(
              url: 'https://example.com/api/search',
              query: {'q': '@keyword'},
            ),
            listPath: r'$.data[*]',
            namePath: r'$.name',
            sourcePath: r'$.id',
          ),
        ),
        episodes: RuleEpisodes(
          mode: 'api',
          apiConfig: ApiChapterConfig(
            request: ApiRequestConfig(url: 'https://example.com/api/videos/@source'),
          ),
        ),
      );

      final result = await engine.search(rule, 'test');

      expect(result.items, hasLength(1));
      expect(result.items.first.title, 'API result');
      expect(result.items.first.sourceId, 'apirule');
    });

    test('queryEpisodes produces MediaEpisodeGroup[] for XPath rule', () async {
      final executor = _FakeExecutor([xpathResponse, xpathResponse]);
      final legacyEngine = RuleEngine(
        requestExecutor: executor,
        logFailures: false,
      );
      final engine = MediaRuleEngine(legacyEngine: legacyEngine);

      final rule = MediaRule(
        version: '9',
        id: 'testrule',
        name: 'TestRule',
        baseUrl: 'https://example.com/',
        search: RuleSearch(
          mode: 'xpath',
          url: 'https://example.com/search?q=@keyword',
          itemXPath: RuleSearchItemXPath(
            itemXPath: '//article[@class="result"]',
            titleXPath: './/h2/a',
            detailUrlXPath: './/h2/a/@href',
          ),
        ),
        episodes: RuleEpisodes(
          mode: 'xpath',
          groupXPath: '//div[@class="road"]',
          itemXPath: RuleEpisodesItemXPath(itemXPath: './/a'),
        ),
      );

      // First search, then query episodes.
      final search = await engine.search(rule, 'alpha');
      final episodeResult = await engine.queryEpisodes(
        rule,
        search.items.first.detailUrl!,
      );

      expect(episodeResult.groups, hasLength(1));
      expect(episodeResult.groups.first.title, contains('播放线路'));
      expect(episodeResult.groups.first.episodes, hasLength(2));
      expect(episodeResult.groups.first.episodes.first.title, '第1集');
      expect(episodeResult.groups.first.episodes.last.title, '第2集');
      expect(episodeResult.groups.first.episodes.first.url, contains('alpha-1'));
      expect(episodeResult.groups.first.episodes.last.url, contains('alpha-2'));
    });

    test('queryEpisodes produces groups for API rule', () async {
      final executor = _FakeExecutor([apiSearchFixture, apiChapterFixture]);
      final legacyEngine = RuleEngine(
        requestExecutor: executor,
        logFailures: false,
      );
      final engine = MediaRuleEngine(legacyEngine: legacyEngine);

      final rule = MediaRule(
        version: '9',
        id: 'apirule',
        name: 'ApiRule',
        baseUrl: 'https://example.com/',
        search: RuleSearch(
          mode: 'api',
          apiConfig: ApiSearchConfig(
            request: ApiRequestConfig(
              url: 'https://example.com/api/search',
              query: {'q': '@keyword'},
            ),
            listPath: r'$.data[*]',
            namePath: r'$.name',
            sourcePath: r'$.id',
          ),
        ),
        episodes: RuleEpisodes(
          mode: 'api',
          apiConfig: ApiChapterConfig(
            request: ApiRequestConfig(url: 'https://example.com/api/videos/@source'),
            roadsPath: r'$.data.roads[*]',
            roadNamePath: r'$.name',
            episodesPath: r'$.episodes[*]',
            episodeNamePath: r'$.name',
            episodeUrlPath: r'$.url',
          ),
        ),
      );

      final search = await engine.search(rule, 'test');
      final episodeResult = await engine.queryEpisodes(
        rule,
        search.items.first.detailUrl!,
      );

      expect(episodeResult.groups, hasLength(1));
      expect(episodeResult.groups.first.title, 'API road');
      expect(episodeResult.groups.first.episodes, hasLength(1));
      expect(episodeResult.groups.first.episodes.first.title, 'Episode 1');
    });

    test('legacy Plugin rule works through toMediaRule()', () async {
      final executor = _FakeExecutor([xpathResponse]);
      final legacyEngine = RuleEngine(
        requestExecutor: executor,
        logFailures: false,
      );
      final engine = MediaRuleEngine(legacyEngine: legacyEngine);

      final plugin = Plugin(
        api: '8',
        type: 'anime',
        name: 'Legacy',
        version: '1.0',
        muliSources: true,
        useWebview: true,
        useNativePlayer: true,
        usePost: false,
        useLegacyParser: false,
        adBlocker: false,
        userAgent: '',
        baseUrl: 'https://example.com/',
        searchURL: 'https://example.com/search?q=@keyword',
        searchList: '//article[@class="result"]',
        searchName: './/h2/a',
        searchResult: './/h2/a/@href',
        chapterRoads: '//div[@class="road"]',
        chapterResult: './/a',
        referer: '',
      );

      final rule = plugin.toMediaRule();
      final result = await engine.search(rule, 'alpha');

      expect(result.items, hasLength(1));
      expect(result.items.first.title, 'Alpha');
      expect(result.items.first.sourceId, 'legacy');
    });

    test('search enriches items with cover from v9 XPath', () async {
      const enrichedHtml = '''
<html>
  <article class="result">
    <h2><a href="/video/test">Test Show</a></h2>
    <img src="https://example.com/cover.jpg" />
    <p>A great show</p>
    <span class="year">2024</span>
  </article>
</html>
''';

      final executor = _FakeExecutor([enrichedHtml]);
      final legacyEngine = RuleEngine(
        requestExecutor: executor,
        logFailures: false,
      );
      final engine = MediaRuleEngine(legacyEngine: legacyEngine);

      final rule = MediaRule(
        version: '9',
        id: 'enriched',
        name: 'Enriched',
        baseUrl: 'https://example.com/',
        search: RuleSearch(
          mode: 'xpath',
          url: 'https://example.com/search?q=@keyword',
          itemXPath: RuleSearchItemXPath(
            itemXPath: '//article[@class="result"]',
            titleXPath: './/h2/a',
            detailUrlXPath: './/h2/a/@href',
            coverXPath: './/img/@src',
            descriptionXPath: './/p/text()',
            yearXPath: './/span[@class="year"]/text()',
          ),
        ),
        episodes: RuleEpisodes(
          mode: 'xpath',
          groupXPath: '//div[@class="road"]',
          itemXPath: RuleEpisodesItemXPath(itemXPath: './/a'),
        ),
      );

      final result = await engine.search(rule, 'test');

      expect(result.items, hasLength(1));
      expect(result.items.first.title, 'Test Show');
      // Cover and year enrichment depends on the HTML structure.
      // The enrichment runs after the basic items are created.
      expect(result.items.first.cover, isNotNull);
      expect(result.items.first.year, isNotNull);
    });

    test('search throws NoResultException for empty results', () async {
      final executor = _FakeExecutor(['<html><body>no results</body></html>']);
      final legacyEngine = RuleEngine(
        requestExecutor: executor,
        logFailures: false,
      );
      final engine = MediaRuleEngine(legacyEngine: legacyEngine);

      final rule = MediaRule(
        version: '9',
        id: 'test',
        name: 'Test',
        baseUrl: 'https://example.com/',
        search: RuleSearch(
          mode: 'xpath',
          url: 'https://example.com/search?q=@keyword',
          itemXPath: RuleSearchItemXPath(
            itemXPath: '//article',
            titleXPath: './/h2/a',
            detailUrlXPath: './/h2/a/@href',
          ),
        ),
        episodes: RuleEpisodes(mode: 'xpath'),
      );

      await expectLater(
        engine.search(rule, 'nothing'),
        throwsA(isA<NoResultException>()),
      );
    });

    test('queryDetail returns null when no detail XPath configured', () async {
      final executor = _FakeExecutor([xpathResponse]);
      final legacyEngine = RuleEngine(
        requestExecutor: executor,
        logFailures: false,
      );
      final engine = MediaRuleEngine(legacyEngine: legacyEngine);

      final rule = MediaRule(
        version: '9',
        id: 'test',
        name: 'Test',
        baseUrl: 'https://example.com/',
        search: RuleSearch(
          mode: 'xpath',
          url: 'https://example.com/search',
          itemXPath: RuleSearchItemXPath(itemXPath: '//article'),
        ),
        episodes: RuleEpisodes(mode: 'xpath'),
      );

      final detail = await engine.queryDetail(rule, 'https://example.com/test');

      expect(detail, isNull);
    });
  });

  group('PluginMediaRuleConversion', () {
    test('toMediaRule() returns a valid MediaRule', () {
      final plugin = Plugin(
        api: '8',
        type: 'anime',
        name: 'TestPlugin',
        version: '1.0',
        muliSources: true,
        useWebview: true,
        useNativePlayer: true,
        usePost: false,
        useLegacyParser: false,
        adBlocker: false,
        userAgent: '',
        baseUrl: 'https://example.com/',
        searchURL: 'https://example.com/search',
        searchList: '//div',
        searchName: '//h3',
        searchResult: '//a',
        chapterRoads: '//ul',
        chapterResult: '//li',
        referer: '',
      );

      final rule = plugin.toMediaRule();

      expect(rule.version, '9');
      expect(rule.id, 'testplugin');
      expect(rule.name, 'TestPlugin');
      expect(rule.baseUrl, 'https://example.com/');
      expect(rule.type, MediaType.anime);
      expect(rule.search, isNotNull);
      expect(rule.episodes, isNotNull);
      expect(rule.stream, isNotNull);
    });
  });
}

class _FakeExecutor implements RuleRequestExecutor {
  _FakeExecutor(List<String> responses, {this.error})
      : _responses = List<String>.of(responses);

  final List<String> _responses;
  final Object? error;
  final List<PreparedRuleRequest> requests = [];

  @override
  Future<String> execute(
    PreparedRuleRequest request,
    RuleExecutionConfig config, {
    CancelToken? cancelToken,
  }) async {
    requests.add(request);
    if (error != null) throw error!;
    return _responses.removeAt(0);
  }
}
