import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/media/collected_media.dart';
import 'package:kazumi/modules/media/media_detail.dart';
import 'package:kazumi/modules/media/media_item.dart';
import 'package:kazumi/modules/media/media_rule.dart';
import 'package:kazumi/modules/media/media_source.dart';
import 'package:kazumi/modules/media/media_stream.dart';
import 'package:kazumi/modules/media/media_type.dart';

void main() {
  group('MediaType', () {
    test('fromString parses known types', () {
      expect(MediaType.fromString('movie'), MediaType.movie);
      expect(MediaType.fromString('tv'), MediaType.tv);
      expect(MediaType.fromString('anime'), MediaType.anime);
      expect(MediaType.fromString('variety'), MediaType.variety);
      expect(MediaType.fromString('documentary'), MediaType.documentary);
      expect(MediaType.fromString('sports'), MediaType.sports);
      expect(MediaType.fromString('mv'), MediaType.mv);
      expect(MediaType.fromString('video'), MediaType.video);
      expect(MediaType.fromString('other'), MediaType.other);
    });

    test('fromString returns unknown for null or unrecognised', () {
      expect(MediaType.fromString(null), MediaType.unknown);
      expect(MediaType.fromString(''), MediaType.unknown);
      expect(MediaType.fromString('xyz'), MediaType.unknown);
    });

    test('label returns Chinese label', () {
      expect(MediaType.movie.label, '电影');
      expect(MediaType.tv.label, '电视剧');
      expect(MediaType.anime.label, '动漫');
      expect(MediaType.unknown.label, '未知');
    });
  });

  group('MediaItem', () {
    test('constructor sets all fields', () {
      final item = MediaItem(
        id: 'src:1',
        title: '测试',
        sourceId: 'src',
        type: MediaType.movie,
        originalTitle: 'Test',
        cover: 'https://example.com/cover.jpg',
        description: 'desc',
        year: '2024',
        genre: '电影',
        detailUrl: 'https://example.com/detail/1',
        metadata: {'key': 'value'},
      );

      expect(item.id, 'src:1');
      expect(item.title, '测试');
      expect(item.sourceId, 'src');
      expect(item.type, MediaType.movie);
      expect(item.originalTitle, 'Test');
      expect(item.cover, 'https://example.com/cover.jpg');
      expect(item.description, 'desc');
      expect(item.year, '2024');
      expect(item.genre, '电影');
      expect(item.detailUrl, 'https://example.com/detail/1');
      expect(item.metadata?['key'], 'value');
    });

    test('displayTitle prefers title over originalTitle', () {
      final item = MediaItem(id: '1', title: '中文', originalTitle: 'Eng', sourceId: 's');
      expect(item.displayTitle, '中文');

      final item2 = MediaItem(id: '2', title: '', originalTitle: 'Eng', sourceId: 's');
      expect(item2.displayTitle, 'Eng');
    });

    test('copyWith creates modified copy', () {
      final original = MediaItem(id: '1', title: 'A', sourceId: 's');
      final copy = original.copyWith(title: 'B', type: MediaType.tv);

      expect(copy.title, 'B');
      expect(copy.type, MediaType.tv);
      expect(copy.id, '1');
      expect(copy.sourceId, 's');
    });

    test('toJson and fromJson round-trip', () {
      final original = MediaItem(
        id: 'src:42',
        title: 'Title',
        sourceId: 'src',
        type: MediaType.tv,
        originalTitle: 'Orig',
        cover: 'cover.jpg',
        description: 'desc',
        year: '2023',
        genre: 'TV',
        detailUrl: 'https://example.com/42',
        metadata: {'custom': 'data'},
      );

      final json = original.toJson();
      final restored = MediaItem.fromJson(json);

      expect(restored.id, 'src:42');
      expect(restored.title, 'Title');
      expect(restored.sourceId, 'src');
      expect(restored.type, MediaType.tv);
      expect(restored.originalTitle, 'Orig');
      expect(restored.cover, 'cover.jpg');
      expect(restored.description, 'desc');
      expect(restored.year, '2023');
      expect(restored.genre, 'TV');
      expect(restored.detailUrl, 'https://example.com/42');
      expect(restored.metadata?['custom'], 'data');
    });
  });

  group('MediaEpisode', () {
    test('constructor', () {
      final ep = MediaEpisode(
        id: '1',
        title: 'EP1',
        url: 'https://example.com/ep1',
        sourceId: 'src',
        group: 'g1',
      );

      expect(ep.id, '1');
      expect(ep.title, 'EP1');
      expect(ep.url, 'https://example.com/ep1');
      expect(ep.sourceId, 'src');
      expect(ep.group, 'g1');
    });
  });

  group('MediaEpisodeGroup', () {
    test('constructor with episodes', () {
      final group = MediaEpisodeGroup(
        id: 'g1',
        title: '线路1',
        episodes: [
          MediaEpisode(id: '1', title: '第1集', url: 'url1', sourceId: 's'),
          MediaEpisode(id: '2', title: '第2集', url: 'url2', sourceId: 's'),
        ],
      );

      expect(group.id, 'g1');
      expect(group.title, '线路1');
      expect(group.episodes.length, 2);
      expect(group.episodes[0].title, '第1集');
      expect(group.episodes[1].title, '第2集');
    });
  });

  group('MediaDetail', () {
    test('toItem converts to MediaItem', () {
      final detail = MediaDetail(
        id: 'src:1',
        title: 'Test',
        sourceId: 'src',
        type: MediaType.movie,
        cover: 'cover.jpg',
        description: 'desc',
        episodeGroups: [],
      );

      final item = detail.toItem();

      expect(item.id, 'src:1');
      expect(item.title, 'Test');
      expect(item.sourceId, 'src');
      expect(item.type, MediaType.movie);
      expect(item.cover, 'cover.jpg');
      expect(item.description, 'desc');
    });
  });

  group('MediaStream', () {
    test('constructor', () {
      final stream = MediaStream(
        url: 'https://example.com/video.m3u8',
        format: 'hls',
        quality: '1080p',
        headers: {'user-agent': 'TestUA'},
        referer: 'https://example.com/',
        isLive: false,
      );

      expect(stream.url, 'https://example.com/video.m3u8');
      expect(stream.format, 'hls');
      expect(stream.quality, '1080p');
      expect(stream.headers?['user-agent'], 'TestUA');
      expect(stream.referer, 'https://example.com/');
      expect(stream.isLive, isFalse);
    });
  });

  group('MediaSource', () {
    test('copyWith', () {
      final source = MediaSource(
        id: 's1',
        name: 'Source1',
        enabled: true,
        priority: 1,
      );

      final modified = source.copyWith(enabled: false, priority: 5);

      expect(modified.id, 's1');
      expect(modified.name, 'Source1');
      expect(modified.enabled, isFalse);
      expect(modified.priority, 5);
    });
  });

  group('CollectedMedia', () {
    test('key returns mediaItem id', () {
      final item = MediaItem(id: 'src:1', title: 'T', sourceId: 's');
      final collected = CollectedMedia(
        mediaItem: item,
        time: DateTime(2024, 1, 1),
        type: 1,
      );

      expect(collected.key, 'src:1');
    });

    test('toJson and fromJson round-trip', () {
      final original = CollectedMedia(
        mediaItem: MediaItem(
          id: 'src:1',
          title: 'Title',
          sourceId: 'src',
          type: MediaType.tv,
        ),
        time: DateTime(2024, 6, 15, 10, 30),
        type: 2,
      );

      final json = original.toJson();
      final restored = CollectedMedia.fromJson(json);

      expect(restored.mediaItem.id, 'src:1');
      expect(restored.mediaItem.title, 'Title');
      expect(restored.type, 2);
      expect(restored.time, DateTime(2024, 6, 15, 10, 30));
    });
  });

  group('MediaRule', () {
    test('isV9 returns true when search is set', () {
      final rule = MediaRule(
        version: '9',
        id: 'test',
        name: 'Test',
        search: RuleSearch(mode: 'xpath', url: 'https://example.com'),
      );

      expect(rule.isV9, isTrue);
      expect(rule.isLegacy, isFalse);
    });

    test('isLegacy returns true when search is null', () {
      final rule = MediaRule(version: '8', id: 'test', name: 'Test');

      expect(rule.isLegacy, isTrue);
      expect(rule.isV9, isFalse);
    });
  });
}
