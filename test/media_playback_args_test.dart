import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/media/media_detail.dart';
import 'package:kazumi/modules/media/media_item.dart';
import 'package:kazumi/modules/media/media_type.dart';
import 'package:kazumi/pages/video/media_playback_args.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/media/media_item_adapter.dart';

void main() {
  group('MediaPlaybackArgs', () {
    test('toVideoPlaybackArgs converts Bangumi-backed item', () {
      final mediaItem = MediaItem(
        id: 'bangumi:42',
        title: '中文名',
        originalTitle: 'OriginalName',
        sourceId: 'bangumi',
        type: MediaType.anime,
        cover: 'cover.jpg',
        description: 'desc',
        metadata: {
          'bangumiId': 42,
          'bangumiType': 2,
          'airDate': '2020-01-01',
          'airWeekday': 3,
          'rank': 5,
          'ratingScore': 8.5,
          'votes': 100,
          'votesCount': <int>[],
          'info': '',
        },
      );

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

      final episodeGroups = [
        MediaEpisodeGroup(
          id: 'group_0',
          title: '播放线路1',
          episodes: [
            MediaEpisode(id: '0', title: '第1集', url: 'https://example.com/play/1', sourceId: 'TestRule'),
            MediaEpisode(id: '1', title: '第2集', url: 'https://example.com/play/2', sourceId: 'TestRule'),
          ],
        ),
      ];

      final args = MediaPlaybackArgs(
        mediaItem: mediaItem,
        plugin: plugin,
        episodeGroups: episodeGroups,
        src: 'https://example.com/detail/42',
      );

      final videoArgs = args.toVideoPlaybackArgs();

      expect(videoArgs, isA<OnlineVideoPlaybackArgs>());

      final onlineArgs = videoArgs;
      expect(onlineArgs.bangumiItem.id, 42);
      expect(onlineArgs.bangumiItem.name, 'OriginalName');
      expect(onlineArgs.bangumiItem.nameCn, '中文名');
      expect(onlineArgs.plugin.name, 'TestRule');
      expect(onlineArgs.title, '中文名');
      expect(onlineArgs.src, 'https://example.com/detail/42');
      expect(onlineArgs.roads, hasLength(1));
      expect(onlineArgs.roads.first.name, '播放线路1');
      expect(onlineArgs.roads.first.data, hasLength(2));
      expect(onlineArgs.roads.first.data[0], 'https://example.com/play/1');
      expect(onlineArgs.roads.first.data[1], 'https://example.com/play/2');
      expect(onlineArgs.roads.first.identifier, hasLength(2));
      expect(onlineArgs.roads.first.identifier[0], '第1集');
      expect(onlineArgs.roads.first.identifier[1], '第2集');
    });

    test('toVideoPlaybackArgs converts non-Bangumi item with synthetic id',
        () {
      final mediaItem = MediaItem(
        id: 'customSource:abc',
        title: 'Custom Show',
        sourceId: 'customSource',
        cover: 'https://example.com/cover.jpg',
      );

      final plugin = Plugin(
        api: '8',
        type: 'anime',
        name: 'CustomRule',
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

      final args = MediaPlaybackArgs(
        mediaItem: mediaItem,
        plugin: plugin,
        episodeGroups: [],
      );

      final videoArgs = args.toVideoPlaybackArgs();

      // Synthetic ID is deterministic and inside the synthetic range.
      expect(
          MediaItemAdapter.isSyntheticBangumiId(videoArgs.bangumiItem.id),
          isTrue);
      expect(videoArgs.bangumiItem.nameCn, 'Custom Show');
      expect(videoArgs.bangumiItem.images['large'],
          'https://example.com/cover.jpg');
      expect(videoArgs.plugin.name, 'CustomRule');
      expect(videoArgs.title, 'Custom Show');

      // Same media ID maps to the same synthetic ID (stable history keys).
      final again = MediaPlaybackArgs(
        mediaItem: mediaItem,
        plugin: plugin,
        episodeGroups: [],
      ).toVideoPlaybackArgs();
      expect(again.bangumiItem.id, videoArgs.bangumiItem.id);

      // Different media IDs map to different synthetic IDs.
      final other = MediaPlaybackArgs(
        mediaItem: MediaItem(
          id: 'customSource:other',
          title: 'Other',
          sourceId: 'customSource',
        ),
        plugin: plugin,
        episodeGroups: [],
      ).toVideoPlaybackArgs();
      expect(other.bangumiItem.id, isNot(videoArgs.bangumiItem.id));
    });

    test('toVideoPlaybackArgs converts multiple episode groups to roads', () {
      final mediaItem = MediaItem(
        id: 'bangumi:1',
        title: 'Test',
        sourceId: 'bangumi',
        metadata: {
          'bangumiId': 1,
          'bangumiType': 2,
          'airDate': '',
          'airWeekday': 0,
          'rank': 0,
          'ratingScore': 0.0,
          'votes': 0,
          'votesCount': <int>[],
          'info': '',
        },
      );

      final plugin = Plugin(
        api: '8',
        type: 'anime',
        name: 'Test',
        version: '1',
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
      );

      final episodeGroups = [
        MediaEpisodeGroup(
          id: 'g0',
          title: '线路1',
          episodes: [
            MediaEpisode(id: '0_0', title: 'EP1', url: 'url1', sourceId: 'Test'),
          ],
        ),
        MediaEpisodeGroup(
          id: 'g1',
          title: '线路2',
          episodes: [
            MediaEpisode(id: '1_0', title: 'EP1', url: 'url2', sourceId: 'Test'),
            MediaEpisode(id: '1_1', title: 'EP2', url: 'url3', sourceId: 'Test'),
          ],
        ),
      ];

      final args = MediaPlaybackArgs(
        mediaItem: mediaItem,
        plugin: plugin,
        episodeGroups: episodeGroups,
      );

      final videoArgs = args.toVideoPlaybackArgs();

      expect(videoArgs.roads, hasLength(2));
      expect(videoArgs.roads[0].name, '线路1');
      expect(videoArgs.roads[0].data, ['url1']);
      expect(videoArgs.roads[1].name, '线路2');
      expect(videoArgs.roads[1].data, ['url2', 'url3']);
    });
  });
}
