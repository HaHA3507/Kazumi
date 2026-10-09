import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/media/media_rule.dart';
import 'package:kazumi/modules/media/media_type.dart';
import 'package:kazumi/plugins/api_rule_config.dart';
import 'package:kazumi/services/media/media_rule_engine.dart';
import 'package:kazumi/services/media/media_search_service.dart';
import 'package:kazumi/services/plugin/rule_engine.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';

void main() {
  const xpathResponseA = '''
<html>
  <article class="result"><h2><a href="/video/alpha">Alpha</a></h2></article>
  <div class="road"><a href="/play/alpha-1">第1集</a></div>
</html>
''';

  const xpathResponseB = '''
<html>
  <article class="result"><h2><a href="/movie/beta">Beta</a></h2></article>
  <div class="road"><a href="/play/beta-1">第1集</a></div>
</html>
''';

  const xpathResponseDup = '''
<html>
  <article class="result"><h2><a href="/show/alpha">Alpha</a></h2></article>
  <div class="road"><a href="/play/alpha-1">第1集</a></div>
</html>
''';

  group('MediaSearchService', () {
    test('searchAll aggregates results from multiple rules', () async {
      final executor = _FakeExecutor([xpathResponseA, xpathResponseB]);
      final legacyEngine = RuleEngine(
        requestExecutor: executor,
        logFailures: false,
      );
      final engine = MediaRuleEngine(legacyEngine: legacyEngine);
      final service = MediaSearchService(engine);

      final ruleA = _makeRule('ruleA', 'https://a.example.com/');
      final ruleB = _makeRule('ruleB', 'https://b.example.com/');

      final response = await service.searchAll([ruleA, ruleB], 'test');

      expect(response.allItems, hasLength(2));
      expect(response.results, hasLength(2));
      expect(response.statusByRule['ruleA'], MediaSearchStatus.success);
      expect(response.statusByRule['ruleB'], MediaSearchStatus.success);
      expect(response.hasResults, isTrue);
      expect(response.isComplete, isTrue);
    });

    test('searchAll deduplicates across sources', () async {
      final executor = _FakeExecutor([xpathResponseA, xpathResponseDup]);
      final legacyEngine = RuleEngine(
        requestExecutor: executor,
        logFailures: false,
      );
      final engine = MediaRuleEngine(legacyEngine: legacyEngine);
      final service = MediaSearchService(engine);

      final ruleA = _makeRule('ruleA', 'https://a.example.com/');
      final ruleB = _makeRule('ruleB', 'https://b.example.com/');

      final response = await service.searchAll([ruleA, ruleB], 'alpha');

      // Two raw results (one from each rule), but same title "Alpha" → 1 group.
      expect(response.allItems, hasLength(2));
      expect(response.results, hasLength(1));
      expect(response.results.first.title, 'Alpha');
      expect(response.results.first.variants, hasLength(2));
      expect(response.results.first.sourceIds, ['ruleA', 'ruleB']);
    });

    test('searchAll reports noResult status for empty results', () async {
      final executor = _FakeExecutor([
        '<html><body>nothing</body></html>',
        xpathResponseB,
      ]);
      final legacyEngine = RuleEngine(
        requestExecutor: executor,
        logFailures: false,
      );
      final engine = MediaRuleEngine(legacyEngine: legacyEngine);
      final service = MediaSearchService(engine);

      final ruleA = _makeRule('ruleA', 'https://a.example.com/');
      final ruleB = _makeRule('ruleB', 'https://b.example.com/');

      final response = await service.searchAll([ruleA, ruleB], 'test');

      expect(response.statusByRule['ruleA'], MediaSearchStatus.noResult);
      expect(response.statusByRule['ruleB'], MediaSearchStatus.success);
      expect(response.allItems, hasLength(1));
    });

    test('searchAll reports error status for failed rule', () async {
      final executor = _FakeExecutor(
        const [],
        error: StateError('connection refused'),
      );
      final legacyEngine = RuleEngine(
        requestExecutor: executor,
        logFailures: false,
      );
      final engine = MediaRuleEngine(legacyEngine: legacyEngine);
      final service = MediaSearchService(engine);

      final ruleA = _makeRule('ruleA', 'https://a.example.com/');

      final response = await service.searchAll([ruleA], 'test');

      expect(response.statusByRule['ruleA'], MediaSearchStatus.error);
      expect(response.errorByRule['ruleA'], isNotNull);
    });

    test('onRuleComplete callback fires per rule', () async {
      final executor = _FakeExecutor([xpathResponseA, xpathResponseB]);
      final legacyEngine = RuleEngine(
        requestExecutor: executor,
        logFailures: false,
      );
      final engine = MediaRuleEngine(legacyEngine: legacyEngine);
      final service = MediaSearchService(engine);

      final ruleA = _makeRule('ruleA', 'https://a.example.com/');
      final ruleB = _makeRule('ruleB', 'https://b.example.com/');

      final callbacks = <String, (MediaSearchStatus, int)>{};

      await service.searchAll(
        [ruleA, ruleB],
        'test',
        onRuleComplete: (ruleId, status, items) {
          callbacks[ruleId] = (status, items.length);
        },
      );

      expect(callbacks, hasLength(2));
      expect(callbacks['ruleA']?.$1, MediaSearchStatus.success);
      expect(callbacks['ruleA']?.$2, 1);
      expect(callbacks['ruleB']?.$1, MediaSearchStatus.success);
      expect(callbacks['ruleB']?.$2, 1);
    });

    test('single rule search returns MediaSearchResult', () async {
      final executor = _FakeExecutor([xpathResponseA]);
      final legacyEngine = RuleEngine(
        requestExecutor: executor,
        logFailures: false,
      );
      final engine = MediaRuleEngine(legacyEngine: legacyEngine);
      final service = MediaSearchService(engine);

      final rule = _makeRule('single', 'https://example.com/');

      final result = await service.search(rule, 'alpha');

      expect(result.items, hasLength(1));
      expect(result.items.first.title, 'Alpha');
      expect(result.items.first.sourceId, 'single');
    });

    test('cancel discards in-flight results', () async {
      final executor = _FakeExecutor([]);
      final legacyEngine = RuleEngine(
        requestExecutor: executor,
        logFailures: false,
      );
      final engine = MediaRuleEngine(legacyEngine: legacyEngine);
      final service = MediaSearchService(engine);

      final rule = _makeRule('test', 'https://example.com/');

      // Cancel immediately.
      service.cancel();

      final response = await service.searchAll([rule], 'test');

      // Cancelled search returns empty results.
      expect(response.results, isEmpty);
    });

    test('handles API mode rules', () async {
      final apiFixture = jsonEncode({
        'data': [
          {'name': 'API Show', 'id': 'show-1'},
        ],
      });
      final executor = _FakeExecutor([apiFixture]);
      final legacyEngine = RuleEngine(
        requestExecutor: executor,
        logFailures: false,
      );
      final engine = MediaRuleEngine(legacyEngine: legacyEngine);
      final service = MediaSearchService(engine);

      final rule = MediaRule(
        version: '9',
        id: 'apirule',
        name: 'ApiRule',
        baseUrl: 'https://api.example.com/',
        search: RuleSearch(
          mode: 'api',
          apiConfig: ApiSearchConfig(
            request: ApiRequestConfig(
              url: 'https://api.example.com/search',
              query: {'q': '@keyword'},
            ),
            listPath: r'$.data[*]',
            namePath: r'$.name',
            sourcePath: r'$.id',
          ),
        ),
        episodes: RuleEpisodes(mode: 'api'),
      );

      final response = await service.searchAll([rule], 'test');

      expect(response.statusByRule['apirule'], MediaSearchStatus.success);
      expect(response.allItems, hasLength(1));
      expect(response.allItems.first.title, 'API Show');
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
  _FakeExecutor(List<String> responses, {this.error})
      : _responses = List<String>.of(responses);

  final List<String> _responses;
  final Object? error;

  @override
  Future<String> execute(
    PreparedRuleRequest request,
    RuleExecutionConfig config, {
    CancelToken? cancelToken,
  }) async {
    if (error != null) throw error!;
    if (_responses.isEmpty) return '<html><body>empty</body></html>';
    return _responses.removeAt(0);
  }
}
