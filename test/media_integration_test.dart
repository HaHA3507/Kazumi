import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/media/media_detail.dart';
import 'package:kazumi/modules/media/media_item.dart';
import 'package:kazumi/modules/media/media_rule.dart';
import 'package:kazumi/modules/media/media_type.dart';
import 'package:kazumi/pages/video/media_playback_args.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/api_rule_config.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/media/media_episode_service.dart';
import 'package:kazumi/services/media/media_rule_engine.dart';
import 'package:kazumi/services/media/media_search_service.dart';
import 'package:kazumi/services/media/plugin_rule_extension.dart';
import 'package:kazumi/services/plugin/rule_engine.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';

void main() {
  group('Integration: search → detail → episodes → playback', () {
    test('complete XPath flow produces playable MediaPlaybackArgs', () async {
      // Mock responses: search page, then episode page.
      const searchHtml = '''
<html>
  <article class="result">
    <h2><a href="/detail/42">庆余年</a></h2>
  </article>
  <article class="result">
    <h2><a href="/detail/43">庆余年第二季</a></h2>
  </article>
</html>
''';

      const episodeHtml = '''
<html>
  <div class="road">
    <a href="/play/ep1">第1集</a>
    <a href="/play/ep2">第2集</a>
    <a href="/play/ep3">第3集</a>
  </div>
</html>
''';

      final executor = _FakeExecutor([searchHtml, episodeHtml]);
      final legacyEngine = RuleEngine(
        requestExecutor: executor,
        logFailures: false,
      );
      final mediaEngine = MediaRuleEngine(legacyEngine: legacyEngine);
      final searchService = MediaSearchService(engine: mediaEngine);
      final episodeService = MediaEpisodeService(engine: mediaEngine);

      // Step 1: Create a rule.
      final rule = MediaRule(
        version: '9',
        id: 'testsource',
        name: 'TestSource',
        baseUrl: 'https://example.com/',
        type: MediaType.tv,
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

      // Step 2: Search.
      final searchResponse = await searchService.searchAll([rule], '庆余年');

      expect(searchResponse.hasResults, isTrue);
      expect(searchResponse.allItems, hasLength(2));
      expect(searchResponse.results, hasLength(2));

      final firstResult = searchResponse.results.first;
      expect(firstResult.title, '庆余年');
      expect(firstResult.primary.detailUrl, isNotNull);

      // Step 3: Query episodes.
      final episodeResult = await episodeService.queryEpisodes(
        rule,
        firstResult.primary,
      );

      expect(episodeResult.groups, hasLength(1));
      expect(episodeResult.groups.first.episodes, hasLength(3));
      expect(episodeResult.groups.first.episodes[0].title, '第1集');
      expect(episodeResult.groups.first.episodes[2].title, '第3集');

      // Step 4: Create playback args.
      // For this test, we simulate a Bangumi-backed item.
      final bangumiBackedItem = MediaItem(
        id: 'bangumi:42',
        title: '庆余年',
        sourceId: 'testsource',
        type: MediaType.tv,
        detailUrl: firstResult.primary.detailUrl,
        metadata: {
          'bangumiId': 42,
          'bangumiType': 2,
          'airDate': '2019-01-01',
          'airWeekday': 1,
          'rank': 10,
          'ratingScore': 8.0,
          'votes': 5000,
          'votesCount': <int>[],
          'info': '',
        },
      );

      final plugin = Plugin(
        api: '8',
        type: 'tv',
        name: 'TestSource',
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

      final playbackArgs = MediaPlaybackArgs(
        mediaItem: bangumiBackedItem,
        plugin: plugin,
        episodeGroups: episodeResult.groups,
        src: 'https://example.com/detail/42',
      );

      // Step 5: Convert to existing VideoPlaybackArgs.
      final videoArgs = playbackArgs.toVideoPlaybackArgs();

      expect(videoArgs, isNotNull);
      expect(videoArgs, isA<OnlineVideoPlaybackArgs>());

      final onlineArgs = videoArgs as OnlineVideoPlaybackArgs;
      expect(onlineArgs.bangumiItem.id, 42);
      expect(onlineArgs.bangumiItem.nameCn, '庆余年');
      expect(onlineArgs.plugin.name, 'TestSource');
      expect(onlineArgs.roads, hasLength(1));
      expect(onlineArgs.roads.first.data, hasLength(3));
      expect(onlineArgs.roads.first.identifier[0], '第1集');

      // Verify executor was called exactly twice (search + episodes).
      expect(executor.callCount, 2);
    });

    test('legacy Plugin rule works through full flow', () async {
      const searchHtml = '''
<html>
  <article class="result"><h2><a href="/video/beta">Beta</a></h2></article>
  <div class="road"><a href="/play/beta-1">第1集</a></div>
</html>
''';

      final executor = _FakeExecutor([searchHtml, searchHtml]);
      final legacyEngine = RuleEngine(
        requestExecutor: executor,
        logFailures: false,
      );
      final mediaEngine = MediaRuleEngine(legacyEngine: legacyEngine);
      final searchService = MediaSearchService(engine: mediaEngine);
      final episodeService = MediaEpisodeService(engine: mediaEngine);

      // Create a legacy Plugin and convert to MediaRule.
      final plugin = Plugin(
        api: '8',
        type: 'anime',
        name: 'LegacySource',
        version: '1.0',
        muliSources: true,
        useWebview: true,
        useNativePlayer: true,
        usePost: false,
        useLegacyParser: false,
        adBlocker: false,
        userAgent: '',
        baseUrl: 'https://example.org/',
        searchURL: 'https://example.org/search?q=@keyword',
        searchList: '//article[@class="result"]',
        searchName: './/h2/a',
        searchResult: './/h2/a/@href',
        chapterRoads: '//div[@class="road"]',
        chapterResult: './/a',
        referer: '',
      );

      final rule = plugin.toMediaRule();

      // Search.
      final searchResponse = await searchService.searchAll([rule], 'beta');

      expect(searchResponse.allItems, hasLength(1));
      expect(searchResponse.allItems.first.title, 'Beta');
      expect(searchResponse.allItems.first.sourceId, 'legacysource');

      // Query episodes.
      final episodeResult = await episodeService.queryEpisodes(
        rule,
        searchResponse.allItems.first,
      );

      expect(episodeResult.groups, hasLength(1));
      expect(episodeResult.groups.first.episodes, hasLength(1));
      expect(episodeResult.groups.first.episodes.first.title, '第1集');
    });

    test('multi-rule search deduplicates across sources', () async {
      const htmlA = '''
<html>
  <article class="result"><h2><a href="/a/1">SameTitle</a></h2></article>
</html>
''';
      const htmlB = '''
<html>
  <article class="result"><h2><a href="/b/1">SameTitle</a></h2></article>
</html>
''';

      final executor = _FakeExecutor([htmlA, htmlB]);
      final legacyEngine = RuleEngine(
        requestExecutor: executor,
        logFailures: false,
      );
      final mediaEngine = MediaRuleEngine(legacyEngine: legacyEngine);
      final searchService = MediaSearchService(engine: mediaEngine);

      final ruleA = _makeRule('sourceA', 'https://a.example.com/');
      final ruleB = _makeRule('sourceB', 'https://b.example.com/');

      final response = await searchService.searchAll([ruleA, ruleB], 'test');

      expect(response.allItems, hasLength(2));
      expect(response.results, hasLength(1));
      expect(response.results.first.title, 'SameTitle');
      expect(response.results.first.variants, hasLength(2));
      expect(response.results.first.sourceIds, ['sourceA', 'sourceB']);
    });
  });
}

MediaRule _makeRule(String id, String baseUrl) {
  return MediaRule(
    version: '9',
    id: id,
    name: id,
    baseUrl: baseUrl,
    type: MediaType.video,
    search: RuleSearch(
      mode: 'xpath',
      url: '$baseUrl/search?q=@keyword',
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
}

class _FakeExecutor implements RuleRequestExecutor {
  _FakeExecutor(List<String> responses)
      : _responses = List<String>.of(responses);

  final List<String> _responses;
  int callCount = 0;

  @override
  Future<String> execute(
    PreparedRuleRequest request,
    RuleExecutionConfig config, {
    CancelToken? cancelToken,
  }) async {
    callCount++;
    if (_responses.isEmpty) return '<html><body>empty</body></html>';
    return _responses.removeAt(0);
  }
}
