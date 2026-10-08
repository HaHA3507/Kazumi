import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/media/media_item.dart';
import 'package:kazumi/modules/media/media_rule.dart';
import 'package:kazumi/services/media/media_detail_service.dart';
import 'package:kazumi/services/media/media_episode_service.dart';
import 'package:kazumi/services/media/media_rule_engine.dart';
import 'package:kazumi/services/plugin/rule_engine.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:dio/dio.dart';

void main() {
  const detailHtml = '''
<html>
  <div class="cover"><img src="https://example.com/real-cover.jpg"></div>
  <div class="desc">A detailed description from the detail page.</div>
  <span class="year">2024</span>
  <span class="genre">电视剧</span>
</html>
''';

  const episodeHtml = '''
<html>
  <div class="road">
    <a href="/play/1">第1集</a>
    <a href="/play/2">第2集</a>
    <a href="/play/3">第3集</a>
  </div>
</html>
''';

  group('MediaDetailService', () {
    test('queryDetail returns null when rule has no detail XPath', () async {
      final executor = _FakeExecutor([episodeHtml]);
      final legacyEngine = RuleEngine(
        requestExecutor: executor,
        logFailures: false,
      );
      final engine = MediaRuleEngine(legacyEngine: legacyEngine);
      final service = MediaDetailService(engine: engine);

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

      final item = MediaItem(
        id: 'test:1',
        title: 'Test',
        sourceId: 'test',
        detailUrl: 'https://example.com/detail/1',
      );

      final detail = await service.queryDetail(rule, item);

      expect(detail, isNull);
    });

    test('queryDetail returns metadata when rule has detail XPath', () async {
      final executor = _FakeExecutor([detailHtml]);
      final legacyEngine = RuleEngine(
        requestExecutor: executor,
        logFailures: false,
      );
      final engine = MediaRuleEngine(legacyEngine: legacyEngine);
      final service = MediaDetailService(engine: engine);

      final rule = MediaRule(
        version: '9',
        id: 'test',
        name: 'Test',
        baseUrl: 'https://example.com/',
        detail: RuleDetail(
          coverXPath: '//div[@class="cover"]//img/@src',
          descriptionXPath: '//div[@class="desc"]/text()',
          yearXPath: '//span[@class="year"]/text()',
          genreXPath: '//span[@class="genre"]/text()',
        ),
        search: RuleSearch(
          mode: 'xpath',
          url: 'https://example.com/search',
          itemXPath: RuleSearchItemXPath(itemXPath: '//article'),
        ),
        episodes: RuleEpisodes(
          mode: 'xpath',
          groupXPath: '//div[@class="road"]',
          itemXPath: RuleEpisodesItemXPath(itemXPath: './/a'),
        ),
      );

      final item = MediaItem(
        id: 'test:1',
        title: 'Test Show',
        sourceId: 'test',
        detailUrl: 'https://example.com/detail/1',
      );

      final detail = await service.queryDetail(rule, item);

      expect(detail, isNotNull);
      // The detail service should merge with the search item's metadata.
      expect(detail!.id, 'test:1');
      expect(detail.title, 'Test Show');
      expect(detail.sourceId, 'test');
    });

    test('queryDetail returns null for empty detailUrl', () async {
      final engine = MediaRuleEngine(
        legacyEngine: RuleEngine(logFailures: false),
      );
      final service = MediaDetailService(engine: engine);

      final rule = MediaRule(
        version: '9',
        id: 'test',
        name: 'Test',
        baseUrl: 'https://example.com/',
        detail: RuleDetail(coverXPath: '//img/@src'),
        search: RuleSearch(mode: 'xpath', url: ''),
        episodes: RuleEpisodes(mode: 'xpath'),
      );

      final item = MediaItem(
        id: 'test:1',
        title: 'Test',
        sourceId: 'test',
        // no detailUrl
      );

      final detail = await service.queryDetail(rule, item);

      expect(detail, isNull);
    });
  });

  group('MediaEpisodeService', () {
    test('queryEpisodes returns episode groups', () async {
      final executor = _FakeExecutor([episodeHtml]);
      final legacyEngine = RuleEngine(
        requestExecutor: executor,
        logFailures: false,
      );
      final engine = MediaRuleEngine(legacyEngine: legacyEngine);
      final service = MediaEpisodeService(engine: engine);

      final rule = MediaRule(
        version: '9',
        id: 'test',
        name: 'Test',
        baseUrl: 'https://example.com/',
        search: RuleSearch(
          mode: 'xpath',
          url: 'https://example.com/search',
          itemXPath: RuleSearchItemXPath(
            itemXPath: '//article',
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

      final item = MediaItem(
        id: 'test:1',
        title: 'Test',
        sourceId: 'test',
        detailUrl: 'https://example.com/detail/1',
      );

      final result = await service.queryEpisodes(rule, item);

      expect(result.groups, hasLength(1));
      expect(result.groups.first.episodes, hasLength(3));
      expect(result.groups.first.episodes[0].title, '第1集');
      expect(result.groups.first.episodes[1].title, '第2集');
      expect(result.groups.first.episodes[2].title, '第3集');
    });

    test('queryAllEpisodes returns flat list', () async {
      final executor = _FakeExecutor([episodeHtml]);
      final legacyEngine = RuleEngine(
        requestExecutor: executor,
        logFailures: false,
      );
      final engine = MediaRuleEngine(legacyEngine: legacyEngine);
      final service = MediaEpisodeService(engine: engine);

      final rule = MediaRule(
        version: '9',
        id: 'test',
        name: 'Test',
        baseUrl: 'https://example.com/',
        search: RuleSearch(
          mode: 'xpath',
          url: 'https://example.com/search',
          itemXPath: RuleSearchItemXPath(
            itemXPath: '//article',
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

      final item = MediaItem(
        id: 'test:1',
        title: 'Test',
        sourceId: 'test',
        detailUrl: 'https://example.com/detail/1',
      );

      final episodes = await service.queryAllEpisodes(rule, item);

      expect(episodes, hasLength(3));
      expect(episodes[0].title, '第1集');
      expect(episodes[2].title, '第3集');
    });

    test('queryEpisodes throws when detailUrl is null', () async {
      final engine = MediaRuleEngine(
        legacyEngine: RuleEngine(logFailures: false),
      );
      final service = MediaEpisodeService(engine: engine);

      final rule = MediaRule(
        version: '9',
        id: 'test',
        name: 'Test',
        baseUrl: 'https://example.com/',
        search: RuleSearch(mode: 'xpath', url: ''),
        episodes: RuleEpisodes(mode: 'xpath'),
      );

      final item = MediaItem(
        id: 'test:1',
        title: 'Test',
        sourceId: 'test',
        // no detailUrl
      );

      await expectLater(
        service.queryEpisodes(rule, item),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

class _FakeExecutor implements RuleRequestExecutor {
  _FakeExecutor(List<String> responses) : _responses = List<String>.of(responses);

  final List<String> _responses;

  @override
  Future<String> execute(
    PreparedRuleRequest request,
    RuleExecutionConfig config, {
    CancelToken? cancelToken,
  }) async {
    if (_responses.isEmpty) return '<html><body>empty</body></html>';
    return _responses.removeAt(0);
  }
}
