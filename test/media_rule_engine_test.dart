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

    test('heuristic cover extracts <img src> for legacy rules (7sefun)',
        () async {
      // Structure taken from 7sefun's real search page.
      const searchHtml = '''
<html>
  <body>
    <div class="videos">
      <div class="video">
        <a class="video-wrapper" href="/voddetail/36123.html">
          <img class="videoimg" src="http://p.qpic.cn/music_cover/abc/600" alt="斗罗大陆" />
        </a>
        <a href="/voddetail/36123.html">斗罗大陆</a>
      </div>
    </div>
  </body>
</html>
''';

      final executor = _FakeExecutor([searchHtml]);
      final legacyEngine = RuleEngine(
        requestExecutor: executor,
        logFailures: false,
      );
      final engine = MediaRuleEngine(legacyEngine: legacyEngine);

      // Legacy v8-style rule: no cover XPath at all.
      final rule = MediaRule(
        version: '9',
        id: 'sefun',
        name: '7sefun',
        baseUrl: 'https://www.7sefun.top/',
        search: RuleSearch(
          mode: 'xpath',
          url: 'https://www.7sefun.top/vodsearch/-------------.html?wd=@keyword',
          itemXPath: RuleSearchItemXPath(
            itemXPath: '//div[@class="video"]',
            titleXPath: './/a[contains(@href,"voddetail")][2]',
            detailUrlXPath: './/a[contains(@href,"voddetail")]/@href',
          ),
        ),
        episodes: RuleEpisodes(mode: 'xpath'),
      );

      final result = await engine.search(rule, '斗罗大陆');

      expect(result.items, hasLength(1));
      expect(result.items.first.cover, 'http://p.qpic.cn/music_cover/abc/600');
    });

    test('heuristic cover extracts <a data-bg> for legacy rules (DM84)',
        () async {
      // Structure taken from DM84's real search page: the poster is a
      // lazy <a> element with data-bg, NOT an <img> tag.
      const searchHtml = '''
<html>
  <body>
    <ul>
      <li>
        <div class="item">
          <a href="/v/4183.html" class="cover lazy" data-bg="https://puui.qpic.cn/vcover_vt_pic/0/xyz/260" title="斗罗大陆2：绝世唐门"></a>
          <a class="title" href="/v/4183.html" title="斗罗大陆2：绝世唐门">斗罗大陆2：绝世唐门</a>
          <span class="desc">第173话</span>
        </div>
      </li>
    </ul>
  </body>
</html>
''';

      final executor = _FakeExecutor([searchHtml]);
      final legacyEngine = RuleEngine(
        requestExecutor: executor,
        logFailures: false,
      );
      final engine = MediaRuleEngine(legacyEngine: legacyEngine);

      // Legacy v8-style rule matching DM84's XPath shape.
      final rule = MediaRule(
        version: '9',
        id: 'dm84',
        name: 'DM84',
        baseUrl: 'https://dmbus.cc/',
        search: RuleSearch(
          mode: 'xpath',
          url: 'https://dmbus.cc/s----------.html?wd=@keyword',
          itemXPath: RuleSearchItemXPath(
            itemXPath: '//ul/li',
            titleXPath: './/div/a[2]',
            detailUrlXPath: './/div/a[2]/@href',
          ),
        ),
        episodes: RuleEpisodes(mode: 'xpath'),
      );

      final result = await engine.search(rule, '斗罗大陆');

      expect(result.items, hasLength(1));
      expect(result.items.first.title, '斗罗大陆2：绝世唐门');
      // The poster comes from the data-bg attribute of the cover link.
      expect(
          result.items.first.cover, 'https://puui.qpic.cn/vcover_vt_pic/0/xyz/260');
    });

    test('queryHome parses recommendations with heuristic cover', () async {
      // Structure shaped like a typical site home page: a hot list where
      // each card is an <a> carrying the href, a title span and an <img>.
      const homeHtml = '''
<html>
  <body>
    <div class="hot">
      <a class="card" href="/v/1.html"><img src="https://example.com/c1.jpg"/><span>推荐一</span></a>
      <a class="card" href="/v/2.html"><span>推荐二</span></a>
    </div>
  </body>
</html>
''';

      final executor = _FakeExecutor([homeHtml]);
      final legacyEngine = RuleEngine(
        requestExecutor: executor,
        logFailures: false,
      );
      final engine = MediaRuleEngine(legacyEngine: legacyEngine);

      final rule = MediaRule(
        version: '9',
        id: 'hotsite',
        name: 'HotSite',
        baseUrl: 'https://example.com/',
        home: RuleHome(
          url: 'https://example.com/hot.html',
          itemXPath: RuleSearchItemXPath(
            itemXPath: '//a[@class="card"]',
            titleXPath: './span',
            detailUrlXPath: './@href',
          ),
        ),
      );

      final result = await engine.queryHome(rule);

      expect(result.items, hasLength(2));
      expect(result.items[0].title, '推荐一');
      expect(result.items[0].sourceId, 'hotsite');
      expect(result.items[0].detailUrl, 'https://example.com/v/1.html');
      // Heuristic cover extraction from the embedded <img>.
      expect(result.items[0].cover, 'https://example.com/c1.jpg');
      expect(result.items[1].title, '推荐二');
      expect(result.items[1].detailUrl, 'https://example.com/v/2.html');
      // The executor fetched the configured home URL, not the base URL.
      expect(executor.requests, hasLength(1));
      expect(executor.requests.first.url, 'https://example.com/hot.html');
      expect(executor.requests.first.method, 'GET');
    });

    test('queryHome parses DM84-shaped home with data-bg cover', () async {
      // Structure taken from DM84's real home page: each item is a
      // div.item containing a lazy cover link (<a data-bg>) and a title
      // link whose element text is the name and href is the detail URL —
      // exactly the element-selection semantics the legacy parser uses.
      const homeHtml = '''
<html>
  <body>
    <ul class="v_list">
      <li><div class="item">
        <a href="/v/71.html" class="cover lazy" data-bg="http://p.qpic.cn/cover/71/600" title="海贼王在线观看"></a>
        <a class="title" href="/v/71.html" title="海贼王">海贼王</a>
        <span class="desc">第1122话</span>
      </div></li>
      <li><div class="item">
        <a href="/v/4342.html" class="cover lazy" data-bg="http://p.qpic.cn/cover/4342/600" title="仙逆在线观看"></a>
        <a class="title" href="/v/4342.html" title="仙逆">仙逆</a>
        <span class="desc">第30话</span>
      </div></li>
    </ul>
  </body>
</html>
''';

      final executor = _FakeExecutor([homeHtml]);
      final legacyEngine = RuleEngine(
        requestExecutor: executor,
        logFailures: false,
      );
      final engine = MediaRuleEngine(legacyEngine: legacyEngine);

      // Mirrors the shipped assets/plugins/DM84.json homeConfig.
      final rule = MediaRule(
        version: '9',
        id: 'dm84',
        name: 'DM84',
        baseUrl: 'https://dmbus.cc/',
        home: RuleHome(
          url: 'https://dmbus.cc/',
          itemXPath: RuleSearchItemXPath(
            itemXPath: '//div[@class="item"]',
            titleXPath: './/a[@class="title"]',
            detailUrlXPath: './/a[@class="title"]',
            coverXPath: './/a/@data-bg',
          ),
        ),
      );

      final result = await engine.queryHome(rule);

      expect(result.items, hasLength(2));
      expect(result.items[0].title, '海贼王');
      expect(result.items[0].detailUrl, 'https://dmbus.cc/v/71.html');
      expect(result.items[0].cover, 'http://p.qpic.cn/cover/71/600');
      expect(result.items[1].title, '仙逆');
      expect(result.items[1].detailUrl, 'https://dmbus.cc/v/4342.html');
      expect(result.items[1].cover, 'http://p.qpic.cn/cover/4342/600');
    });

    test('queryHome falls back to baseUrl when home url is empty', () async {
      const homeHtml = '''
<html>
  <body>
    <div class="hot">
      <a class="card" href="/v/9.html"><span>推荐九</span></a>
    </div>
  </body>
</html>
''';

      final executor = _FakeExecutor([homeHtml]);
      final legacyEngine = RuleEngine(
        requestExecutor: executor,
        logFailures: false,
      );
      final engine = MediaRuleEngine(legacyEngine: legacyEngine);

      final rule = MediaRule(
        version: '9',
        id: 'hotsite',
        name: 'HotSite',
        baseUrl: 'https://example.com/',
        home: RuleHome(
          itemXPath: RuleSearchItemXPath(
            itemXPath: '//a[@class="card"]',
            titleXPath: './span',
            detailUrlXPath: './@href',
          ),
        ),
      );

      final result = await engine.queryHome(rule);

      expect(result.items, hasLength(1));
      expect(result.items.first.title, '推荐九');
      expect(executor.requests.first.url, 'https://example.com/');
    });

    test('queryHome throws when rule has no home config', () async {
      final engine = MediaRuleEngine(
        legacyEngine: RuleEngine(logFailures: false),
      );

      final rule = MediaRule(
        version: '9',
        id: 'plain',
        name: 'Plain',
        baseUrl: 'https://example.com/',
      );

      await expectLater(
        engine.queryHome(rule),
        throwsA(isA<StateError>()),
      );
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
  _FakeExecutor(List<String> responses)
      : _responses = List<String>.of(responses);

  final List<String> _responses;
  final List<PreparedRuleRequest> requests = [];

  @override
  Future<String> execute(
    PreparedRuleRequest request,
    RuleExecutionConfig config, {
    CancelToken? cancelToken,
  }) async {
    requests.add(request);
    if (_responses.isEmpty) return '<html><body>empty</body></html>';
    return _responses.removeAt(0);
  }
}
