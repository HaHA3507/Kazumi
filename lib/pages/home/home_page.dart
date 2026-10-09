import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/card/media_card.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/history/history_controller.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/media/media_item_adapter.dart';
import 'package:kazumi/services/player/history_playback_service.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;
import 'package:kazumi/utils/device.dart';

/// Universal home page — search bar, continue watching, favorites, sources.
///
/// Replaces the Bangumi-centric PopularPage. Content is sourced from the
/// existing HistoryController and CollectController (via adapter) until
/// Phase 7 migrates the data layer to MediaItem.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with KazumiDialogOwner {
  late PluginsController _pluginsController;
  late HistoryController _historyController;
  late CollectController _collectController;

  @override
  void initState() {
    super.initState();
    _pluginsController = inject<PluginsController>();
    _historyController = inject<HistoryController>();
    _collectController = inject<CollectController>();
  }

  void _navigateToSearch() {
    context.pushNamed('/media_search/');
  }

  void _navigateToDetail(BangumiItem item) {
    context.pushNamed('/info/', arguments: item);
  }

  void _navigateToPluginSettings() {
    context.pushNamed('/settings/plugin/');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: const Text('Kazumi'),
            floating: true,
            pinned: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.rule),
                onPressed: _navigateToPluginSettings,
                tooltip: '规则管理',
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: _buildSearchBar(context, theme),
          ),
          SliverToBoxAdapter(
            child: _buildContinueWatching(context, theme),
          ),
          SliverToBoxAdapter(
            child: _buildFavorites(context, theme),
          ),
          SliverToBoxAdapter(
            child: _buildSources(context, theme),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: InkWell(
        onTap: _navigateToSearch,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Row(
            children: [
              Icon(Icons.search, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Text(
                '搜索任意内容...',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContinueWatching(BuildContext context, ThemeData theme) {
    final histories = _historyController.histories;
    if (histories.isEmpty) return const SizedBox.shrink();

    final recent = histories.take(10).toList();

    return _Section(
      title: '继续观看',
      child: SizedBox(
        height: 220,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: recent.length,
          itemBuilder: (context, index) {
            final history = recent[index];
            return _ContinueWatchingCard(
              history: history,
              onTap: () => _resumePlayback(history),
            );
          },
        ),
      ),
    );
  }

  Future<void> _resumePlayback(History history) async {
    final playbackService = inject<HistoryPlaybackService>();
    await dialogs.run((task) async {
      final cancelToken = RuleCancelToken();
      final result = await task.loading(
        message: '获取中',
        barrierDismissible: isDesktop(),
        onCancel: cancelToken.cancel,
        action: () =>
            playbackService.open(history, cancelToken: cancelToken),
      );
      switch (result) {
        case HistoryPlaybackReady(:final args):
          task.withContext(
              (context) => context.pushNamed('/video/', arguments: args));
        case HistoryPlaybackUnavailable(:final reason):
          KazumiDialog.showToast(message: reason);
      }
    }, errorMessage: '暂时无法继续播放，请稍后重试');
  }

  Widget _buildFavorites(BuildContext context, ThemeData theme) {
    final collectibles = _collectController.collectibles
        .where((c) => c.type != CollectType.none.value)
        .toList();
    if (collectibles.isEmpty) return const SizedBox.shrink();

    final favorites = collectibles.take(6).toList();

    return _Section(
      title: '我的收藏',
      child: SizedBox(
        height: 200,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: favorites.length,
          itemBuilder: (context, index) {
            final collected = favorites[index];
            final mediaItem = MediaItemAdapter.fromBangumiItem(
              collected.bangumiItem,
            );
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: MediaCard(
                item: mediaItem,
                width: 130,
                height: 200,
                onTap: () => _navigateToDetail(collected.bangumiItem),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSources(BuildContext context, ThemeData theme) {
    final allPlugins = _pluginsController.pluginList;
    final enabledPlugins = allPlugins.where((p) => p.enabled).toList();

    return _Section(
      title: '内容来源 (${enabledPlugins.length}/${allPlugins.length})',
      trailing: TextButton(
        onPressed: _navigateToPluginSettings,
        child: const Text('管理'),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: enabledPlugins.map((plugin) {
            return ActionChip(
              label: Text(plugin.name),
              avatar: const Icon(Icons.source_outlined, size: 18),
              onPressed: () {
                context.pushNamed('/settings/plugin/editor',
                    arguments: plugin);
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              ?trailing,
            ],
          ),
        ),
        child,
      ],
    );
  }
}

/// Continue-watching card showing cover, title, episode name, and a
/// progress indicator. Tapping resumes playback.
class _ContinueWatchingCard extends StatelessWidget {
  const _ContinueWatchingCard({
    required this.history,
    required this.onTap,
  });

  final History history;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaItem = history.mediaItem;
    final cardWidth = 150.0;
    final cardHeight = 210.0;

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: cardWidth,
          height: cardHeight,
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCover(context, cardWidth, cardHeight * 0.55),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mediaItem.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          history.displayEpisodeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const Spacer(),
                        if (history.hasProgress)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: 0.5,
                              minHeight: 3,
                              backgroundColor:
                                  theme.colorScheme.surfaceContainerHighest,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCover(BuildContext context, double width, double height) {
    final cover = history.mediaItem.cover;
    if (cover == null || cover.isEmpty) {
      return Container(
        width: width,
        height: height,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.play_circle_outline,
          size: 40,
          color: Theme.of(context)
              .colorScheme
              .onSurfaceVariant
              .withValues(alpha: 0.4),
        ),
      );
    }
    return Stack(
      children: [
        Image.network(
          cover,
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (context, url, error) => Container(
            width: width,
            height: height,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
        Positioned(
          bottom: 4,
          right: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(
              Icons.play_arrow,
              size: 16,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}
