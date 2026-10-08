import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/modules/media/media_item.dart';
import 'package:kazumi/modules/media/media_type.dart';

void main() {
  group('History.mediaItem getter', () {
    test('returns MediaItem with correct fields', () {
      final bangumi = BangumiItem(
        id: 42,
        type: 2,
        name: 'OriginalName',
        nameCn: '中文名',
        summary: 'desc',
        airDate: '2020-01-01',
        airWeekday: 3,
        rank: 5,
        images: {'large': 'cover.jpg'},
        tags: [],
        alias: ['Alt'],
        ratingScore: 8.5,
        votes: 100,
        votesCount: [],
        info: '',
      );

      final history = History(
        bangumi,
        1,
        'myPlugin',
        DateTime(2024, 6, 15),
        'https://example.com/ep1',
        '第1集',
      );

      final media = history.mediaItem;

      expect(media.id, 'myPlugin:42');
      expect(media.title, '中文名');
      expect(media.originalTitle, 'OriginalName');
      expect(media.cover, 'cover.jpg');
      expect(media.sourceId, 'myPlugin');
      expect(media.type, MediaType.anime);
    });

    test('displayEpisodeName returns stored name', () {
      final bangumi = BangumiItem(
        id: 1,
        type: 2,
        name: 'Test',
        nameCn: 'Test',
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

      final history = History(
        bangumi,
        5,
        'plugin',
        DateTime.now(),
        'url',
        '第5集 - 标题',
      );

      expect(history.displayEpisodeName, '第5集 - 标题');
    });

    test('displayEpisodeName falls back to default when empty', () {
      final bangumi = BangumiItem(
        id: 1,
        type: 2,
        name: 'Test',
        nameCn: 'Test',
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

      final history = History(
        bangumi,
        3,
        'plugin',
        DateTime.now(),
        'url',
        '', // empty episode name
      );

      expect(history.displayEpisodeName, '第3集');
    });

    test('hasProgress returns true when progress exists', () {
      final bangumi = BangumiItem(
        id: 1,
        type: 2,
        name: 'Test',
        nameCn: 'Test',
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

      final history = History(
        bangumi,
        1,
        'plugin',
        DateTime.now(),
        'url',
        'EP1',
      );
      history.progresses[1] = Progress(1, 0, 30000);

      expect(history.hasProgress, isTrue);
    });

    test('hasProgress returns false when no progress', () {
      final bangumi = BangumiItem(
        id: 1,
        type: 2,
        name: 'Test',
        nameCn: 'Test',
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

      final history = History(
        bangumi,
        0,
        'plugin',
        DateTime.now(),
        'url',
        '',
      );

      expect(history.hasProgress, isFalse);
    });

    test('mediaItemId returns stable string ID', () {
      final bangumi = BangumiItem(
        id: 99,
        type: 2,
        name: 'Test',
        nameCn: 'Test',
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

      final history = History(
        bangumi,
        1,
        'mySource',
        DateTime.now(),
        'url',
        'EP1',
      );

      expect(history.mediaItemId, 'mysource:99');
    });
  });

  group('CollectedBangumi.mediaItem getter', () {
    test('returns MediaItem with correct fields', () {
      final bangumi = BangumiItem(
        id: 55,
        type: 2,
        name: 'Anime',
        nameCn: '动漫',
        summary: 'description',
        airDate: '2023-04-01',
        airWeekday: 6,
        rank: 10,
        images: {'large': 'cover.jpg'},
        tags: [],
        alias: [],
        ratingScore: 9.0,
        votes: 500,
        votesCount: [],
        info: '',
      );

      final collected = CollectedBangumi(
        bangumi,
        DateTime(2024, 1, 1),
        CollectType.watching.value,
      );

      final media = collected.mediaItem;

      expect(media.id, 'bangumi:55');
      expect(media.title, '动漫');
      expect(media.originalTitle, 'Anime');
      expect(media.cover, 'cover.jpg');
      expect(media.sourceId, 'bangumi');
      expect(media.type, MediaType.anime);
    });
  });
}
