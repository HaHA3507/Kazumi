import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:html/parser.dart';
import 'package:kazumi/modules/media/media_detail.dart';
import 'package:kazumi/modules/media/media_item.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/media/media_deduplicator.dart';
import 'package:kazumi/services/media/media_episode_service.dart';
import 'package:kazumi/services/media/media_item_adapter.dart';
import 'package:kazumi/services/media/plugin_rule_extension.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';

/// Universal media detail page — shows media info and ALL playback lines
/// from ALL sources that returned this content.
///
/// Accepts a [DeduplicatedMediaItem] (or a plain [MediaItem]) as route
/// argument. Loads episodes from every variant concurrently and displays
/// every episode group (road) of every source, so the user sees the full
/// 线路 list instead of just one.
class MediaDetailPage extends StatefulWidget {
  const MediaDetailPage({super.key, this.item});

  final Object? item;

  @override
  State<MediaDetailPage> createState() => _MediaDetailPageState();
}

class _MediaDetailPageState extends State<MediaDetailPage> {
  late final MediaEpisodeService _episodeService;
  late final PluginsController _pluginsController;

  DeduplicatedMediaItem? _dedupItem;
  MediaItem? _selectedItem;

  List<_SourceEpisodes> _sources = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _episodeService = inject<MediaEpisodeService>();
    _pluginsController = inject<PluginsController>();

    final args = widget.item;
    if (args is DeduplicatedMediaItem) {
      _dedupItem = args;
      _selectedItem = args.primary;
    } else if (args is MediaItem) {
      _selectedItem = args;
      _dedupItem = DeduplicatedMediaItem(
        primary: args,
        variants: [args],
      );
    }

    if (_selectedItem != null) {
      _loadEpisodes();
    }
  }

  /// Loads episodes from EVERY source (dedup variant) concurrently, so the
  /// full line list from all sources is visible at once.
  Future<void> _loadEpisodes() async {
    final variants = _dedupItem?.variants.toList() ?? const <MediaItem>[];
    if (variants.isEmpty) return;

    setState(() => _isLoading = true);

    final results = await Future.wait(
      variants.map((variant) => _loadSourceEpisodes(variant)),
    );

    if (!mounted) return;
    setState(() {
      _sources = results;
      _isLoading = false;
    });
    _fillMissingCover(results);
  }

  Future<_SourceEpisodes> _loadSourceEpisodes(MediaItem item) async {
    final plugin = _findPlugin(item.sourceId);
    if (plugin == null) {
      return _SourceEpisodes(
        plugin: null,
        item: item,
        groups: const [],
        rawHtml: '',
        error: '未找到来源规则: ${item.sourceId}',
      );
    }
    try {
      final result = await _episodeService.queryEpisodes(
        plugin.toMediaRule(),
        item,
      );
      return _SourceEpisodes(
        plugin: plugin,
        item: item,
        groups: result.groups,
        rawHtml: result.rawResponse,
        error: null,
      );
    } catch (error) {
      return _SourceEpisodes(
        plugin: plugin,
        item: item,
        groups: const [],
        rawHtml: '',
        error: error.toString(),
      );
    }
  }

  /// When the primary item still has no cover (search heuristics failed),
  /// try og:image from one of the loaded detail pages.
  void _fillMissingCover(List<_SourceEpisodes> sources) {
    final current = _selectedItem;
    if (current == null || current.cover != null) return;
    for (final source in sources) {
      final ogImage = _extractOgImage(
        source.rawHtml,
        source.plugin?.baseUrl ?? '',
      );
      if (ogImage != null) {
        if (!mounted) return;
        setState(() => _selectedItem = current.copyWith(cover: ogImage));
        return;
      }
    }
  }

  String? _extractOgImage(String html, String baseUrl) {
    if (html.trim().isEmpty) return null;
    try {
      final root = parse(html).documentElement;
      if (root == null) return null;
      final nodes = root.queryXPath('//meta[@property="og:image"]').nodes;
      for (final node in nodes) {
        final content = node.attributes['content']?.trim();
        if (content == null || content.isEmpty) continue;
        if (content.startsWith('http://') ||
            content.startsWith('https://')) {
          return content;
        }
        if (content.startsWith('//')) return 'https:$content';
        final base = Uri.tryParse(baseUrl);
        if (base != null && base.hasScheme) {
          try {
            return base.resolve(content).toString();
          } catch (_) {}
        }
        return content;
      }
    } catch (_) {}
    return null;
  }

  Plugin? _findPlugin(String sourceId) {
    for (final plugin in _pluginsController.pluginList) {
      if (pluginNameKey(plugin.name) == sourceId) {
        return plugin;
      }
    }
    return null;
  }

  /// Plays [episodeIndex] (1-based within [groupIndex]) of [source].
  ///
  /// Passes that source's full road list so in-player line switching keeps
  /// working, plus the explicit start position so the player opens on the
  /// tapped episode instead of the first one.
  void _playEpisode(_SourceEpisodes source, int groupIndex, int episodeIndex) {
    final plugin = source.plugin;
    if (plugin == null) return;
    final item = source.item;

    final bangumiItem = MediaItemAdapter.toPlaybackBangumiItem(item);

    final roads = <Road>[];
    for (final group in source.groups) {
      roads.add(Road(
        name: group.title,
        data: group.episodes.map((e) => e.url).toList(),
        identifier: group.episodes.map((e) => e.title).toList(),
      ));
    }

    final args = OnlineVideoPlaybackArgs(
      bangumiItem: bangumiItem,
      plugin: plugin,
      title: item.displayTitle,
      src: item.detailUrl ?? '',
      roads: roads,
      initialEpisode: episodeIndex + 1,
      initialRoad: groupIndex,
    );

    context.pushNamed('/video/', arguments: args);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = _selectedItem;

    if (item == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('参数无效')),
      );
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(item.displayTitle),
              background: item.cover != null
                  ? CachedNetworkImage(
                      imageUrl: item.cover!,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) => Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                    )
                  : Container(color: theme.colorScheme.surfaceContainerHighest),
            ),
          ),
          SliverToBoxAdapter(
            child: _buildInfoSection(context, theme, item),
          ),
          if (_isLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else
            ..._buildSourceSlivers(context, theme),
        ],
      ),
    );
  }

  Widget _buildInfoSection(
      BuildContext context, ThemeData theme, MediaItem item) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.displayTitle,
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              if (item.originalTitle != null &&
                  item.originalTitle != item.title)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    item.originalTitle!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          if (item.year != null || item.genre != null) ...[
            const SizedBox(height: 4),
            Text(
              [if (item.year != null) item.year!, if (item.genre != null) item.genre!]
                  .join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (item.description != null) ...[
            const SizedBox(height: 12),
            Text(
              item.description!,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildSourceSlivers(BuildContext context, ThemeData theme) {
    if (_sources.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('没有可用的播放来源')),
          ),
        ),
      ];
    }

    final slivers = <Widget>[];
    for (final source in _sources) {
      slivers.add(
        SliverToBoxAdapter(child: _buildSourceHeader(theme, source)),
      );
      if (source.error != null) {
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '加载失败: ${source.error}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          ),
        );
        continue;
      }
      if (source.groups.isEmpty) {
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '没有剧集',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        );
        continue;
      }

      // Always label each line, even single-line sources: users need to
      // see which (and how many) lines a source actually provides.
      final showGroupTitles = source.groups.isNotEmpty;
      for (var groupIndex = 0; groupIndex < source.groups.length; groupIndex++) {
        final group = source.groups[groupIndex];
        if (showGroupTitles) {
          slivers.add(
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Text(group.title, style: theme.textTheme.titleSmall),
              ),
            ),
          );
        }
        slivers.add(
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 100,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.5,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, episodeIndex) {
                  final episode = group.episodes[episodeIndex];
                  return FilledButton.tonal(
                    onPressed: () =>
                        _playEpisode(source, groupIndex, episodeIndex),
                    child: Text(
                      episode.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
                childCount: group.episodes.length,
              ),
            ),
          ),
        );
      }
    }

    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 32)));
    return slivers;
  }

  Widget _buildSourceHeader(ThemeData theme, _SourceEpisodes source) {
    final name = source.plugin?.name ?? source.item.sourceId;
    final total = source.groups.fold<int>(
      0,
      (sum, group) => sum + group.episodes.length,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(
            Icons.source_outlined,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (source.error == null && total > 0)
            Text(
              '$total 集 · ${source.groups.length} 线路',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// Episodes loaded from one source (dedup variant), kept together with the
/// plugin so playback can use the correct headers and road list.
class _SourceEpisodes {
  const _SourceEpisodes({
    required this.plugin,
    required this.item,
    required this.groups,
    required this.rawHtml,
    required this.error,
  });

  final Plugin? plugin;
  final MediaItem item;
  final List<MediaEpisodeGroup> groups;
  final String rawHtml;
  final String? error;
}
