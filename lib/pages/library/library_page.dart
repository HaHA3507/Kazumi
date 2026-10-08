import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/card/media_card.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/modules/media/media_item.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/services/media/bangumi_item_adapter.dart';

/// Universal library page — collected media grid with type filters.
///
/// Replaces the Bangumi-centric CollectPage. Reads from the existing
/// CollectController (via adapter) until Phase 7 migrates the data layer.
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  late CollectController _collectController;
  int _selectedFilterIndex = 0;

  static const _filters = [
    ('全部', null),
    ('在看', CollectType.watching),
    ('想看', CollectType.planToWatch),
    ('看过', CollectType.watched),
    ('搁置', CollectType.onHold),
    ('抛弃', CollectType.abandoned),
  ];

  @override
  void initState() {
    super.initState();
    _collectController = Modular.get<CollectController>();
  }

  List<CollectedBangumi> get _filtered {
    final type = _filters[_selectedFilterIndex].$2;
    if (type == null) {
      return _collectController.collectibles
          .where((c) => c.type != CollectType.none.value)
          .toList();
    }
    return _collectController.collectibles
        .where((c) => c.type == type.value)
        .toList();
  }

  void _navigateToDetail(BangumiItem item) {
    Modular.to.pushNamed('/info/', arguments: item);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: const Text('媒体库'),
            floating: true,
            pinned: false,
          ),
          SliverToBoxAdapter(
            child: _buildFilterChips(theme),
          ),
          Observer(
            builder: (context) {
              final items = _filtered;
              if (items.isEmpty) {
                return SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.library_books_outlined,
                          size: 64,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '还没有收藏',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 160,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.65,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final collected = items[index];
                      final mediaItem =
                          BangumiItemAdapter.fromBangumiItem(
                        collected.bangumiItem,
                      );
                      return MediaCard(
                        item: mediaItem,
                        onTap: () =>
                            _navigateToDetail(collected.bangumiItem),
                      );
                    },
                    childCount: items.length,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(ThemeData theme) {
    return SizedBox(
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _filters.length,
        itemBuilder: (context, index) {
          final (label, _) = _filters[index];
          final selected = index == _selectedFilterIndex;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(label),
              selected: selected,
              onSelected: (_) {
                setState(() => _selectedFilterIndex = index);
              },
            ),
          );
        },
      ),
    );
  }
}
