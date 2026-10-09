import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/bangumi_tag.dart';
import 'package:kazumi/modules/media/media_item.dart';
import 'package:kazumi/modules/media/media_type.dart';
import 'package:kazumi/services/media/media_item_adapter.dart';

void main() {
  group('MediaItemAdapter', () {
    test('fromBangumiItem converts all core fields', () {
      final bangumi = BangumiItem(
        id: 12345,
        type: 2,
        name: '進撃の巨人',
        nameCn: '进击的巨人',
        summary: '人類vs巨人',
        airDate: '2013-04-06',
        airWeekday: 6,
        rank: 100,
        images: {'large': 'https://example.com/cover.jpg'},
        tags: [BangumiTag(name: '热血', count: 500, totalCount: 600)],
        alias: ['Shingeki', 'AoT'],
        ratingScore: 8.5,
        votes: 10000,
        votesCount: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        info: 'extra info',
      );

      final media = MediaItemAdapter.fromBangumiItem(bangumi);

      expect(media.id, 'bangumi:12345');
      expect(media.title, '进击的巨人');
      expect(media.originalTitle, '進撃の巨人');
      expect(media.cover, 'https://example.com/cover.jpg');
      expect(media.description, '人類vs巨人');
      expect(media.year, '2013');
      expect(media.sourceId, 'bangumi');
      expect(media.type, MediaType.anime);
      expect(media.metadata?['bangumiId'], 12345);
      expect(media.metadata?['airWeekday'], 6);
      expect(media.metadata?['ratingScore'], 8.5);
    });

    test('fromBangumiItem falls back to name when nameCn empty', () {
      final bangumi = BangumiItem(
        id: 1,
        type: 2,
        name: 'OriginalName',
        nameCn: '',
        summary: '',
        airDate: '',
        airWeekday: 0,
        rank: 0,
        images: {},
        tags: [],
        alias: [],
        ratingScore: 0,
        votes: 0,
        votesCount: [],
        info: '',
      );

      final media = MediaItemAdapter.fromBangumiItem(bangumi);

      expect(media.title, 'OriginalName');
      expect(media.originalTitle, isNull);
    });

    test('fromBangumiItem supports custom sourceId', () {
      final bangumi = BangumiItem(
        id: 99,
        type: 2,
        name: 'Test',
        nameCn: '测试',
        summary: '',
        airDate: '',
        airWeekday: 0,
        rank: 0,
        images: {},
        tags: [],
        alias: [],
        ratingScore: 0,
        votes: 0,
        votesCount: [],
        info: '',
      );

      final media = MediaItemAdapter.fromBangumiItem(bangumi, sourceId: 'myrule');

      expect(media.id, 'myrule:99');
      expect(media.sourceId, 'myrule');
    });

    test('toBangumiItem round-trips id, name, type', () {
      final media = MediaItem(
        id: 'bangumi:42',
        title: '测试番剧',
        originalTitle: 'TestAnime',
        sourceId: 'bangumi',
        type: MediaType.anime,
        cover: 'https://example.com/cover.jpg',
        description: 'desc',
        metadata: {
          'bangumiId': 42,
          'airDate': '2020-01-01',
          'airWeekday': 3,
          'rank': 50,
          'ratingScore': 7.8,
          'votes': 500,
          'votesCount': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
          'info': '',
          'alias': ['Alt1'],
          'tags': [{'name': 'tag1', 'count': 10, 'total_cont': 20}],
        },
      );

      final bangumi = MediaItemAdapter.toBangumiItem(media);

      expect(bangumi, isNotNull);
      expect(bangumi!.id, 42);
      expect(bangumi.type, 2);
      expect(bangumi.name, 'TestAnime');
      expect(bangumi.nameCn, '测试番剧');
      expect(bangumi.summary, 'desc');
      expect(bangumi.airDate, '2020-01-01');
      expect(bangumi.airWeekday, 3);
      expect(bangumi.images['large'], 'https://example.com/cover.jpg');
      expect(bangumi.alias, ['Alt1']);
      expect(bangumi.tags.length, 1);
      expect(bangumi.tags.first.name, 'tag1');
    });

    test('toBangumiItem returns null for non-bangumi id', () {
      final media = MediaItem(
        id: 'myrule:abc',
        title: 'Test',
        sourceId: 'myrule',
      );

      final result = MediaItemAdapter.toBangumiItem(media);

      expect(result, isNull);
    });

    test('toBangumiItem returns null for unparseable id', () {
      final media = MediaItem(
        id: 'no-colon-here',
        title: 'Test',
        sourceId: 'test',
      );

      final result = MediaItemAdapter.toBangumiItem(media);

      expect(result, isNull);
    });

    test('toPlaybackBangumiItem returns real item for Bangumi-backed id', () {
      final media = MediaItem(
        id: 'bangumi:42',
        title: '测试番剧',
        originalTitle: 'TestAnime',
        sourceId: 'bangumi',
        metadata: {
          'bangumiId': 42,
          'bangumiType': 2,
          'airDate': '2020-01-01',
          'airWeekday': 3,
          'rank': 50,
          'ratingScore': 7.8,
          'votes': 500,
          'votesCount': <int>[],
          'info': '',
        },
      );

      final result = MediaItemAdapter.toPlaybackBangumiItem(media);

      expect(result.id, 42);
      expect(result.nameCn, '测试番剧');
      expect(MediaItemAdapter.isSyntheticBangumiId(result.id), isFalse);
    });

    test('toPlaybackBangumiItem creates deterministic synthetic item', () {
      final media = MediaItem(
        id: 'myrule:https://example.com/detail/abc',
        title: '任意内容',
        sourceId: 'myrule',
        cover: 'https://example.com/cover.jpg',
      );

      final first = MediaItemAdapter.toPlaybackBangumiItem(media);
      final second = MediaItemAdapter.toPlaybackBangumiItem(media);

      // Deterministic: same media ID → same synthetic Bangumi ID.
      expect(first.id, second.id);
      // Inside the synthetic range (901M–1B), never a real Bangumi ID.
      expect(MediaItemAdapter.isSyntheticBangumiId(first.id), isTrue);
      expect(first.id, greaterThanOrEqualTo(901000000));
      expect(first.id, lessThan(1000000000));
      // Core fields are carried over.
      expect(first.nameCn, '任意内容');
      expect(first.images['large'], 'https://example.com/cover.jpg');
    });

    test('synthetic IDs differ for different media IDs', () {
      final a = MediaItemAdapter.syntheticBangumiId('ruleA:item1');
      final b = MediaItemAdapter.syntheticBangumiId('ruleB:item2');

      expect(a, isNot(b));
    });

    test('syntheticBangumiId is stable across calls', () {
      final id = 'myrule:some-detail-url-12345';

      expect(MediaItemAdapter.syntheticBangumiId(id),
          MediaItemAdapter.syntheticBangumiId(id));
    });
  });
}
