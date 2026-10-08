import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/media/media_deduplicator.dart';
import 'package:kazumi/modules/media/media_item.dart';
import 'package:kazumi/modules/media/media_type.dart';

void main() {
  group('MediaDeduplicator', () {
    const dedup = MediaDeduplicator();

    test('groups same title from different sources', () {
      final items = [
        MediaItem(id: 'a:1', title: '庆余年', sourceId: 'a'),
        MediaItem(id: 'b:1', title: '庆余年', sourceId: 'b'),
        MediaItem(id: 'c:1', title: '庆余年', sourceId: 'c'),
      ];

      final result = dedup.deduplicate(items);

      expect(result, hasLength(1));
      expect(result.first.variants, hasLength(3));
      expect(result.first.title, '庆余年');
      expect(result.first.sourceIds, ['a', 'b', 'c']);
      expect(result.first.hasMultipleSources, isTrue);
    });

    test('does not group different titles', () {
      final items = [
        MediaItem(id: 'a:1', title: '庆余年', sourceId: 'a'),
        MediaItem(id: 'a:2', title: '庆余年第二季', sourceId: 'a'),
      ];

      final result = dedup.deduplicate(items);

      expect(result, hasLength(2));
      expect(result[0].title, isNot(equals(result[1].title)));
    });

    test('does not group same title with different years', () {
      final items = [
        MediaItem(id: 'a:1', title: '庆余年', sourceId: 'a', year: '2019'),
        MediaItem(id: 'b:1', title: '庆余年', sourceId: 'b', year: '2024'),
      ];

      final result = dedup.deduplicate(items);

      expect(result, hasLength(2));
    });

    test('groups same title with same year', () {
      final items = [
        MediaItem(id: 'a:1', title: '庆余年', sourceId: 'a', year: '2019'),
        MediaItem(id: 'b:1', title: '庆余年', sourceId: 'b', year: '2019'),
      ];

      final result = dedup.deduplicate(items);

      expect(result, hasLength(1));
      expect(result.first.variants, hasLength(2));
    });

    test('normalizes whitespace and separators', () {
      final items = [
        MediaItem(id: 'a:1', title: ' Breaking Bad ', sourceId: 'a'),
        MediaItem(id: 'b:1', title: 'breaking bad', sourceId: 'b'),
        MediaItem(id: 'c:1', title: 'Breaking-Bad', sourceId: 'c'),
      ];

      final result = dedup.deduplicate(items);

      expect(result, hasLength(1));
      expect(result.first.variants, hasLength(3));
    });

    test('picks best representative (most metadata)', () {
      final items = [
        MediaItem(id: 'a:1', title: 'Test', sourceId: 'a'),
        MediaItem(
          id: 'b:1',
          title: 'Test',
          sourceId: 'b',
          cover: 'cover.jpg',
          description: 'desc',
          year: '2024',
        ),
        MediaItem(
          id: 'c:1',
          title: 'Test',
          sourceId: 'c',
          cover: 'cover2.jpg',
        ),
      ];

      final result = dedup.deduplicate(items);

      expect(result, hasLength(1));
      // Item 'b:1' has the most metadata (cover + description + year = 7 points)
      expect(result.first.primary.id, 'b:1');
      expect(result.first.primary.cover, 'cover.jpg');
    });

    test('sorts by group size (largest first)', () {
      final items = [
        MediaItem(id: 'a:1', title: 'Solo', sourceId: 'a'),
        MediaItem(id: 'b:1', title: 'Group', sourceId: 'b'),
        MediaItem(id: 'c:1', title: 'Group', sourceId: 'c'),
        MediaItem(id: 'd:1', title: 'Group', sourceId: 'd'),
      ];

      final result = dedup.deduplicate(items);

      // 'Group' has 3 sources, should be first.
      expect(result.first.title, 'Group');
      expect(result.first.variants.length, 3);
      expect(result.last.title, 'Solo');
    });

    test('handles empty input', () {
      final result = dedup.deduplicate([]);

      expect(result, isEmpty);
    });

    test('items from same source with same title are grouped', () {
      final items = [
        MediaItem(id: 'a:1', title: 'Same', sourceId: 'a'),
        MediaItem(id: 'a:2', title: 'Same', sourceId: 'a'),
      ];

      final result = dedup.deduplicate(items);

      // Same title should still be grouped even from same source
      expect(result, hasLength(1));
      expect(result.first.variants, hasLength(2));
    });

    test('uses originalTitle when title is empty', () {
      final items = [
        MediaItem(id: 'a:1', title: '', originalTitle: 'OriginalName', sourceId: 'a'),
        MediaItem(id: 'b:1', title: 'OriginalName', sourceId: 'b'),
      ];

      final result = dedup.deduplicate(items);

      expect(result, hasLength(1));
      expect(result.first.variants, hasLength(2));
    });
  });
}
