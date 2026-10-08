import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/media/media_detail.dart';
import 'package:kazumi/modules/media/media_item.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/media/bangumi_item_adapter.dart';
import 'package:kazumi/services/media/media_deduplicator.dart';
import 'package:kazumi/services/media/media_episode_service.dart';
import 'package:kazumi/services/media/plugin_rule_extension.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';

/// Universal media detail page — shows media info and episode groups.
///
/// Replaces the Bangumi-centric InfoPage. Accepts a [DeduplicatedMediaItem]
/// (or a plain [MediaItem]) as route argument. Uses [MediaEpisodeService]
/// to fetch episodes from the selected source.
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
  int _selectedVariantIndex = 0;

  List<MediaEpisodeGroup> _episodeGroups = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _episodeService = Modular.get<MediaEpisodeService>();
    _pluginsController = Modular.get<PluginsController>();

    final args = widget.item;
    if (args is DeduplicatedMediaItem) {
      _dedupItem = args;
      _selectedVariantIndex = 0;
      _selectedItem = args.variants.first;
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

  Future<void> _loadEpisodes() async {
    final item = _selectedItem;
    if (item == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final plugin = _findPlugin(item.sourceId);
    if (plugin == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = '未找到来源规则: ${item.sourceId}';
      });
      return;
    }

    final rule = plugin.toMediaRule();

    try {
      final result = await _episodeService.queryEpisodes(rule, item);
      if (mounted) {
        setState(() {
          _episodeGroups = result.groups;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Plugin? _findPlugin(String sourceId) {
    for (final plugin in _pluginsController.pluginList) {
      if (pluginNameKey(plugin.name) == sourceId) {
        return plugin;
      }
    }
    return null;
  }

  void _selectVariant(int index) {
    setState(() {
      _selectedVariantIndex = index;
      _selectedItem = _dedupItem!.variants[index];
      _episodeGroups = [];
    });
    _loadEpisodes();
  }

  void _playEpisode(int groupIndex, int episodeIndex) {
    final item = _selectedItem;
    if (item == null) return;

    final plugin = _findPlugin(item.sourceId);
    if (plugin == null) return;

    // Convert MediaItem → BangumiItem (adapter for existing video page).
    final bangumiItem = BangumiItemAdapter.toBangumiItem(item);
    if (bangumiItem == null) {
      // Not a Bangumi item — for now, we can't play non-Bangumi items
      // through the existing video page. This will be resolved when
      // the video page is migrated to accept MediaItem (Phase 7+).
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该内容暂不支持播放（非 Bangumi 来源）')),
      );
      return;
    }

    // Convert MediaEpisodeGroup[] → Road[] (adapter for existing video page).
    final roads = <Road>[];
    for (final group in _episodeGroups) {
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
    );

    Modular.to.pushNamed('/video/', arguments: args);
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
                      errorWidget: (context, url, error) =>
                          Container(color: theme.colorScheme.surfaceContainerHighest),
                    )
                  : Container(color: theme.colorScheme.surfaceContainerHighest),
            ),
          ),
          SliverToBoxAdapter(
            child: _buildInfoSection(context, theme, item),
          ),
          if (_dedupItem != null && _dedupItem!.hasMultipleSources)
            SliverToBoxAdapter(
              child: _buildSourceSelector(theme),
            ),
          if (_isLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (_errorMessage != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _errorMessage!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            )
          else
            ..._buildEpisodeSlivers(context, theme),
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

  Widget _buildSourceSelector(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('来源', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _dedupItem!.variants.asMap().entries.map((entry) {
              final index = entry.key;
              final variant = entry.value;
              return ChoiceChip(
                label: Text(variant.sourceId),
                selected: index == _selectedVariantIndex,
                onSelected: (_) => _selectVariant(index),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildEpisodeSlivers(BuildContext context, ThemeData theme) {
    if (_episodeGroups.isEmpty) {
      return [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('没有剧集')),
          ),
        ),
      ];
    }

    final slivers = <Widget>[];
    for (var gi = 0; gi < _episodeGroups.length; gi++) {
      final group = _episodeGroups[gi];
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(group.title, style: theme.textTheme.titleSmall),
          ),
        ),
      );
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
              (context, ei) {
                final episode = group.episodes[ei];
                return FilledButton.tonal(
                  onPressed: () => _playEpisode(gi, ei),
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

    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 32)));
    return slivers;
  }
}
