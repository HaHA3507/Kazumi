import 'package:dio/dio.dart';
import 'package:kazumi/modules/media/media_item.dart';
import 'package:kazumi/modules/media/media_rule.dart';
import 'package:kazumi/services/media/media_deduplicator.dart';
import 'package:kazumi/services/media/media_rule_engine.dart';
import 'package:kazumi/services/media/media_rule_models.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/utils/async_session.dart';

/// Per-rule search status, mirroring the existing [PluginSearchStatus] but
/// decoupled from the Anime domain.
enum MediaSearchStatus { pending, success, noResult, error, captcha }

/// Aggregated search response from all rules.
class MediaSearchResponse {
  /// Deduplicated result groups, sorted by relevance.
  final List<DeduplicatedMediaItem> results;

  /// All raw items before deduplication (for debugging or advanced use).
  final List<MediaItem> allItems;

  /// Per-rule status, keyed by rule ID.
  final Map<String, MediaSearchStatus> statusByRule;

  /// Per-rule error messages, keyed by rule ID (only for error/captcha status).
  final Map<String, String> errorByRule;

  const MediaSearchResponse({
    required this.results,
    required this.allItems,
    required this.statusByRule,
    required this.errorByRule,
  });

  /// Whether any rule returned results.
  bool get hasResults => results.isNotEmpty;

  /// Whether all rules have completed (none still pending).
  bool get isComplete =>
      !statusByRule.values.any((s) => s == MediaSearchStatus.pending);
}

/// Concurrent multi-rule search service.
///
/// Searches all provided rules concurrently via [MediaRuleEngine], aggregates
/// results, and deduplicates across sources using [MediaDeduplicator].
///
/// This service is **UI-agnostic** — it returns data, not observable state.
/// The caller (Phase 5 UI) is responsible for updating the view.
class MediaSearchService {
  MediaSearchService(
    this._engine, {
    MediaDeduplicator deduplicator = const MediaDeduplicator(),
  }) : _deduplicator = deduplicator;

  final MediaRuleEngine _engine;
  final MediaDeduplicator _deduplicator;

  /// Session management for cancellable concurrent search.
  final AsyncSessionOwner _sessionOwner = AsyncSessionOwner();
  CancelToken? _cancelToken;

  /// Searches all rules concurrently for [keyword].
  ///
  /// [rules] — list of enabled rules to search.
  /// [keyword] — search query.
  /// [cancelToken] — optional Dio cancel token for cancellation.
  /// [onRuleComplete] — optional callback invoked per-rule as each completes,
  ///   useful for progressive UI updates.
  ///
  /// Returns aggregated [MediaSearchResponse] when all rules have completed
  /// (or been cancelled).
  Future<MediaSearchResponse> searchAll(
    List<MediaRule> rules,
    String keyword, {
    CancelToken? cancelToken,
    void Function(String ruleId, MediaSearchStatus status, List<MediaItem> items)?
        onRuleComplete,
  }) async {
    final session = _sessionOwner.begin();
    _cancelToken = cancelToken ?? CancelToken();

    final statusByRule = <String, MediaSearchStatus>{};
    final errorByRule = <String, String>{};
    final allItems = <MediaItem>[];

    // Initialize all rules as pending.
    for (final rule in rules) {
      statusByRule[rule.id] = MediaSearchStatus.pending;
    }

    // Search all rules concurrently.
    await Future.wait(
      rules.map((rule) => _searchRule(
        rule,
        keyword,
        session: session,
        statusByRule: statusByRule,
        errorByRule: errorByRule,
        allItems: allItems,
        onRuleComplete: onRuleComplete,
      )),
    );

    if (session.isStale) {
      // A newer search has started; discard results.
      return MediaSearchResponse(
        results: [],
        allItems: [],
        statusByRule: statusByRule,
        errorByRule: errorByRule,
      );
    }

    // Deduplicate.
    final deduplicated = _deduplicator.deduplicate(allItems);

    return MediaSearchResponse(
      results: deduplicated,
      allItems: List.unmodifiable(allItems),
      statusByRule: Map.unmodifiable(statusByRule),
      errorByRule: Map.unmodifiable(errorByRule),
    );
  }

  /// Searches a single rule. Useful for re-searching after captcha verification.
  Future<MediaSearchResult> search(
    MediaRule rule,
    String keyword, {
    CancelToken? cancelToken,
  }) {
    return _engine.search(rule, keyword, cancelToken: cancelToken);
  }

  /// Cancels the current search.
  void cancel() {
    _sessionOwner.cancel();
    _cancelToken?.cancel();
  }

  /// Closes the service, preventing new searches.
  void close() {
    _sessionOwner.close();
    _cancelToken?.cancel();
  }

  Future<void> _searchRule(
    MediaRule rule,
    String keyword, {
    required AsyncSession session,
    required Map<String, MediaSearchStatus> statusByRule,
    required Map<String, String> errorByRule,
    required List<MediaItem> allItems,
    required void Function(String ruleId, MediaSearchStatus status, List<MediaItem> items)?
        onRuleComplete,
  }) async {
    if (session.isStale) return;
    try {
      final result = await _engine.search(
        rule,
        keyword,
        cancelToken: _cancelToken,
      );
      if (session.isStale) return;

      if (result.items.isEmpty) {
        statusByRule[rule.id] = MediaSearchStatus.noResult;
      } else {
        statusByRule[rule.id] = MediaSearchStatus.success;
        allItems.addAll(result.items);
      }
      onRuleComplete?.call(rule.id, statusByRule[rule.id]!, result.items);
    } catch (error) {
      if (session.isStale) return;
      _handleError(rule, error, statusByRule, errorByRule, onRuleComplete);
    }
  }

  void _handleError(
    MediaRule rule,
    Object error,
    Map<String, MediaSearchStatus> statusByRule,
    Map<String, String> errorByRule,
    void Function(String ruleId, MediaSearchStatus status, List<MediaItem> items)?
        onRuleComplete,
  ) {
    if (error is CaptchaRequiredException) {
      statusByRule[rule.id] = MediaSearchStatus.captcha;
      errorByRule[rule.id] = '需要验证码';
      KazumiLogger().i('MediaSearchService: captcha required for ${rule.id}');
    } else if (error is NoResultException) {
      statusByRule[rule.id] = MediaSearchStatus.noResult;
      KazumiLogger().i('MediaSearchService: no results for ${rule.id}');
    } else {
      statusByRule[rule.id] = MediaSearchStatus.error;
      final message = error is SearchErrorException
          ? (error.cause?.toString() ?? '搜索失败')
          : error.toString();
      errorByRule[rule.id] = message;
      KazumiLogger()
          .w('MediaSearchService: search error for ${rule.id}', error: error);
    }
    onRuleComplete?.call(rule.id, statusByRule[rule.id]!, []);
  }
}
