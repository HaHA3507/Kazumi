import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/modules/media/media_item.dart';
import 'package:kazumi/services/media/media_deduplicator.dart';

/// Universal media card — displays a [MediaItem] or [DeduplicatedMediaItem]
/// with cover, title, and optional source badges.
///
/// Used by the home page, library page, and search results.
class MediaCard extends StatelessWidget {
  const MediaCard({
    super.key,
    required this.item,
    this.showSources = false,
    this.onTap,
    this.width,
    this.height,
  });

  final MediaItem item;
  final bool showSources;
  final VoidCallback? onTap;
  final double? width;
  final double? height;

  factory MediaCard.deduplicated({
    Key? key,
    required DeduplicatedMediaItem dedup,
    VoidCallback? onTap,
    double? width,
    double? height,
  }) {
    return MediaCard(
      key: key,
      item: dedup.primary,
      showSources: dedup.hasMultipleSources,
      onTap: onTap,
      width: width,
      height: height,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardWidth = width ?? 160;
    final cardHeight = height ?? 240;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: cardWidth,
        height: cardHeight,
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCover(context, cardWidth, cardHeight * 0.65),
              Expanded(child: _buildInfo(context, theme)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCover(BuildContext context, double width, double height) {
    final cover = item.cover;
    if (cover == null || cover.isEmpty) {
      return Container(
        width: width,
        height: height,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.movie_outlined,
          size: 48,
          color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: cover,
      width: width,
      height: height,
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      errorWidget: (context, url, error) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.broken_image_outlined,
          size: 48,
          color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        ),
      ),
    );
  }

  Widget _buildInfo(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.displayTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          if (item.year != null) ...[
            const SizedBox(height: 2),
            Text(
              item.year!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (showSources) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(
                  Icons.source_outlined,
                  size: 12,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    item.sourceId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
