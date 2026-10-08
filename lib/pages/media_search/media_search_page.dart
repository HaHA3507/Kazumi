import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/card/media_card.dart';
import 'package:kazumi/modules/media/media_item.dart';
import 'package:kazumi/modules/media/media_rule.dart';
import 'package:kazumi/modules/media/media_type.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/media/media_deduplicator.dart';
import 'package:kazumi/services/media/media_search_service.dart';
import 'package:kazumi/services/media/plugin_rule_extension.dart';

/// Universal media search page — concurrent multi-rule search with
/// deduplication.
///
/// Replaces the Bangumi-centric SearchPage. Searches all installed rules
/// via [MediaSearchService] and shows deduplicated results.
class MediaSearchPage extends StatefulWidget {
  const MediaSearchPage({super.key, this.initialKeyword});

  final String? initialKeyword;

  @override
  State<MediaSearchPage> createState() => _MediaSearchPageState();
}

class _MediaSearchPageState extends State<MediaSearchPage> {
  late final TextEditingController _searchController;
  late final MediaSearchService _searchService;
  late final PluginsController _pluginsController;

  List<DeduplicatedMediaItem> _results = [];
  Map<String, MediaSearchStatus> _statusByRule = {};
  bool _isSearching = false;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialKeyword);
    _searchService = Modular.get<MediaSearchService>();
    _pluginsController = Modular.get<PluginsController>();

    if (widget.initialKeyword != null && widget.initialKeyword!.isNotEmpty) {
      _performSearch(widget.initialKeyword!);
    }
  }

  @override
  void dispose() {
    _searchService.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _performSearch(String keyword) {
    if (keyword.trim().isEmpty) return;

    setState(() {
      _isSearching = true;
      _hasSearched = true;
      _results = [];
      _statusByRule = {};
    });

    final rules = _pluginsController.pluginList
        .where((p) => p.enabled)
        .map((p) => p.toMediaRule())
        .toList();

    _searchService.searchAll(rules, keyword).then((response) {
      if (mounted) {
        setState(() {
          _results = response.results;
          _statusByRule = response.statusByRule;
          _isSearching = false;
        });
      }
    });
  }

  void _navigateToDetail(DeduplicatedMediaItem item) {
    // Navigate to the media detail page with the primary item.
    // If there are multiple variants, pass all of them so the detail
    // page can show source selection.
    Modular.to.pushNamed('/media_detail/', arguments: item);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: widget.initialKeyword == null,
          textInputAction: TextInputAction.search,
          onSubmitted: _performSearch,
          decoration: InputDecoration(
            hintText: '搜索任意内容...',
            border: InputBorder.none,
            suffixIcon: IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => _performSearch(_searchController.text),
            ),
          ),
        ),
      ),
      body: _buildBody(context, theme),
    );
  }

  Widget _buildBody(BuildContext context, ThemeData theme) {
    if (!_hasSearched) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('输入关键词开始搜索', style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
          ],
        ),
      );
    }

    if (_isSearching) {
      return Column(
        children: [
          _buildStatusBar(theme),
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sentiment_dissatisfied, size: 64, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('未找到结果', style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildStatusBar(theme),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 160,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.65,
            ),
            itemCount: _results.length,
            itemBuilder: (context, index) {
              return MediaCard.deduplicated(
                dedup: _results[index],
                onTap: () => _navigateToDetail(_results[index]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBar(ThemeData theme) {
    final successCount = _statusByRule.values
        .where((s) => s == MediaSearchStatus.success)
        .length;
    final totalRules = _statusByRule.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            '$successCount/$totalRules 个来源已响应 · ${_results.length} 条结果',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
