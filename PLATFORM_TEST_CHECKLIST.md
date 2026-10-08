# PLATFORM_TEST_CHECKLIST.md

> Phase 8: Platform verification checklist for the Universal XPath Media Shell refactoring.
>
> This document describes manual and automated tests that must be run on
> actual devices after the refactoring is complete.

---

## 1. Automated Test Suite

Run all unit and integration tests:

```bash
flutter test
```

### Test Files (13 total)

| Test File | Tests | What It Covers |
|---|---|---|
| `media_models_test.dart` | 15 | MediaType, MediaItem, MediaEpisode, MediaEpisodeGroup, MediaDetail, MediaStream, MediaSource, CollectedMedia, MediaRule |
| `bangumi_item_adapter_test.dart` | 6 | BangumiItem → MediaItem (all fields, nameCn fallback, custom sourceId), MediaItem → BangumiItem (round-trip, null for non-Bangumi) |
| `legacy_rule_adapter_test.dart` | 8 | Plugin → MediaRule (XPath, API, non-anime, antiCrawler), MediaRule → Plugin (round-trip, v9→v8) |
| `media_rule_engine_test.dart` | 8 | MediaRuleExecutionConfig (v9 fields, legacy fields, toLegacyConfig), MediaRuleEngine (XPath search, API search, XPath episodes, API episodes, legacy Plugin, cover enrichment, empty results, detail) |
| `media_deduplicator_test.dart` | 10 | Same title grouping, different title, different year, same year, whitespace normalization, best representative, sorting, empty input, same source, originalTitle |
| `media_search_service_test.dart` | 7 | Multi-rule aggregation, dedup across sources, noResult status, error status, onRuleComplete callback, single rule search, cancel, API mode |
| `media_history_adapter_test.dart` | 8 | History.mediaItem (fields, displayEpisodeName, hasProgress, mediaItemId), CollectedBangumi.mediaItem |
| `media_detail_episode_service_test.dart` | 5 | MediaDetailService (no detail XPath → null, with detail XPath, empty detailUrl), MediaEpisodeService (queryEpisodes, queryAllEpisodes, null detailUrl throws) |
| `media_playback_args_test.dart` | 3 | MediaPlaybackArgs.toVideoPlaybackArgs (Bangumi-backed, non-Bangumi null, multiple groups) |
| `plugin_enabled_field_test.dart` | 8 | Plugin.fromJson (default true, false, true), toJson (omits when true, includes when false), fromTemplate, round-trip, backward compat |
| `media_integration_test.dart` | 3 | Full XPath flow (search → episodes → playback args), legacy Plugin flow, multi-rule dedup |
| **Existing tests** | 22 | rule_engine_test, api_rule_engine_test, episode_url_test, episode_ref_test, m3u8_parser_test, history_repository_test, history_sync_test, collect_sync_test, bangumi_search_params_test, etc. |
| **Total** | **95** | |

---

## 2. Compile Verification

```bash
flutter analyze
flutter build apk --debug
flutter build ios --debug --no-codesign   # if iOS toolchain available
```

### Expected: 0 errors, 0 warnings (unused imports may show as info)

---

## 3. Android Manual Test Plan

### 3.1 App Launch & Navigation

| # | Test | Steps | Expected |
|---|---|---|---|
| A1 | App launches with new navigation | Install and open app | Bottom nav shows: 首页, 媒体库, 历史, 我的 |
| A2 | Default startup page | Launch app with rules installed | Opens on 首页 (Home) |
| A3 | Tab switching | Tap each tab | Correct page shows for each tab |
| A4 | Old routes still accessible | Navigate to `/tab/popular/` | Popular page loads (backward compat) |
| A5 | Settings default page | Settings → Interface → Default startup page | Shows 首页/媒体库/历史/我的 |

### 3.2 Home Page

| # | Test | Steps | Expected |
|---|---|---|---|
| H1 | Search bar | Tap search bar on home | Navigates to media search page |
| H2 | Continue watching | Play an episode, return to home | "继续观看" section shows card with episode name |
| H3 | Resume playback | Tap a continue watching card | Loading dialog → video player opens at resume position |
| H4 | Favorites preview | Add a favorite, return to home | "我的收藏" section shows the item |
| H5 | Sources list | View sources section | Shows enabled sources with count (enabled/total) |
| H6 | Disabled sources | Disable a source in rule management | Source disappears from home page sources list |

### 3.3 Media Search

| # | Test | Steps | Expected |
|---|---|---|---|
| S1 | Search keyword | Enter keyword on search page, submit | All enabled rules search concurrently |
| S2 | Results display | Wait for search | Deduplicated results in grid |
| S3 | Multi-source dedup | Two sources return same title | Shows as one entry with source badge |
| S4 | Status bar | Observe during search | Shows "N/M sources responded · K results" |
| S5 | Disabled rules excluded | Disable a rule, search | Disabled rule does not participate |
| S6 | Empty results | Search with no results | Shows "未找到结果" |
| S7 | API mode rule | Search with an API-mode rule | Results parsed from JSON response |

### 3.4 Detail Page

| # | Test | Steps | Expected |
|---|---|---|---|
| D1 | Open detail | Tap a search result | Detail page shows cover, title, episodes |
| D2 | Episode groups | View detail page with multi-road rule | Multiple groups shown, each with episode grid |
| D3 | Source selector | Tap a deduplicated result | Shows source selector chips |
| D4 | Switch source | Tap a different source chip | Episodes reload from new source |
| D5 | Play episode | Tap an episode button | Video player opens and plays |

### 3.5 Library Page

| # | Test | Steps | Expected |
|---|---|---|---|
| L1 | Library view | Tap 媒体库 tab | Shows collected items in grid |
| L2 | Filter chips | Tap "在看" filter | Shows only "watching" items |
| L3 | Empty state | Clear all collections | Shows empty state with icon and message |
| L4 | Tap item | Tap a collected item | Navigates to detail page |

### 3.6 History Tab

| # | Test | Steps | Expected |
|---|---|---|---|
| T1 | History view | Tap 历史 tab | Shows watch history list |
| T2 | Resume from history | Tap a history entry | Video player resumes at last position |
| T3 | Delete history | Edit mode → delete entry | Entry removed |
| T4 | Clear all | Edit mode → clear all | All history deleted |

### 3.7 Rule Management (Source Manager)

| # | Test | Steps | Expected |
|---|---|---|---|
| R1 | Enable/disable toggle | Open rule management, toggle a switch | Switch state persists across app restart |
| R2 | Disabled rule excluded | Disable a rule, go to search | Rule not included in search |
| R3 | Re-enable rule | Re-enable a disabled rule | Rule participates in search again |
| R4 | Import rule | Import a `kazumi://` link | Rule installed and enabled by default |
| R5 | Export rule | Share a rule | `kazumi://` link generated |
| R6 | Add new rule | Create rule from template | New rule editor opens |
| R7 | Edit rule | Tap a rule | Editor opens with 4 sections |
| R8 | Test rule | Menu → test rule | Test page opens, search and chapter tests work |
| R9 | Delete rule | Menu → delete rule | Confirmation dialog → rule removed |
| R10 | Reorder rules | Drag handle or menu up/down | Order persists |

### 3.8 Video Player

| # | Test | Steps | Expected |
|---|---|---|---|
| V1 | MP4 playback | Play an MP4 source | Video plays correctly |
| V2 | HLS (M3U8) playback | Play an M3U8 source | HLS stream plays correctly |
| V3 | HTTP headers | Play a source requiring referer | Player sends correct referer header |
| V4 | User-Agent | Play a source requiring custom UA | Player sends correct UA |
| V5 | Resume position | Play from history | Starts at last position |
| V6 | History recording | Watch partially, exit | Progress saved to history |
| V7 | Fullscreen | Tap fullscreen button | Fullscreen mode works |
| V8 | Landscape | Rotate device to landscape | Layout switches to fullscreen-style |
| V9 | PiP | Enable PiP, leave app | Picture-in-picture works |
| V10 | Background playback | Enable in settings, background app | Audio continues playing |
| V11 | Subtitle (if available) | Load a source with subtitles | Subtitles display |
| V12 | Episode switching | Switch episodes in player | New episode loads without error |
| V13 | Danmaku | Play an anime episode with danmaku | Danmaku comments show and sync |

---

## 4. iOS Manual Test Plan

Same as Android (Section 3) with additional checks:

| # | Test | Steps | Expected |
|---|---|---|---|
| I1 | AVPlayer compatibility | Play HLS stream | media_kit uses VideoToolbox HW decoder |
| I2 | WebView (flutter_inappwebview) | Play any source | Video source resolved via WebView |
| I3 | ContentBlocker | Play a source with ads | Ad blocking content blocker active |
| I4 | Background audio | Background the app during playback | Audio session continues |
| I5 | Fullscreen orientation | Enter fullscreen | Forces landscape orientation |
| I6 | PiP | Enter PiP mode | PiP window shows and is controllable |

---

## 5. Desktop Manual Test Plan (if applicable)

| # | Test | Steps | Expected |
|---|---|---|---|
| D1 | Window management | Open/close app | Window state persists |
| D2 | Side rail navigation | Use navigation rail | Tabs switch correctly |
| D3 | System tray | Minimize to tray | Tray icon works, restore works |
| D4 | Keyboard shortcuts | Use player keyboard shortcuts | All shortcuts functional |
| D5 | Proxy settings | Configure proxy in settings | All network traffic uses proxy |

---

## 6. Backward Compatibility Tests

| # | Test | Steps | Expected |
|---|---|---|---|
| B1 | Existing rules | Install app over existing installation | All existing rules preserved and enabled |
| B2 | Existing history | Check history tab | All existing watch history preserved |
| B3 | Existing favorites | Check library tab | All existing favorites preserved |
| B4 | Existing downloads | Check download page | All existing downloads preserved |
| B5 | WebDAV sync | Trigger sync | History syncs correctly with existing format |
| B6 | Old search page | Navigate to `/search/` | Old Bangumi search still works |
| B7 | Old info page | Navigate to `/info/` | Old info page still works |
| B8 | Old video page | Play from old info page | Video player works as before |
| B9 | Bangumi sync | Settings → sync → Bangumi | Bangumi collection sync works |
| B10 | Danmaku | Play anime with danmaku | DanDanPlay danmaku loads correctly |

---

## 7. Format Matrix

| Format | Source Type | Test URL Pattern | Expected |
|---|---|---|---|
| MP4 | Direct URL | `https://example.com/video.mp4` | Plays via media_kit auto-detect |
| HLS | M3U8 URL | `https://example.com/stream.m3u8` | Plays via media_kit with HLS demuxer |
| HLS (encrypted) | M3U8 with KEY | `#EXT-X-KEY:METHOD=AES-128` | Plays if key URI accessible |
| DASH | MPD URL | `https://example.com/stream.mpd` | Auto-detected by MPV lavf |
| Live stream | M3U8 live | `#EXT-X-PLAYLIST-TYPE:EVENT` | Plays without duration |

---

## 8. Regression Checklist

- [ ] `flutter analyze` — 0 errors
- [ ] `flutter test` — all 95+ tests pass
- [ ] `flutter build apk --debug` — builds successfully
- [ ] App launches on Android
- [ ] App launches on iOS (if available)
- [ ] All 4 tabs work (Home, Library, History, My)
- [ ] Search returns results from enabled rules
- [ ] Detail page shows episodes
- [ ] Video player plays MP4 and HLS
- [ ] History records and resumes
- [ ] Favorites display in library
- [ ] Enable/disable toggle persists
- [ ] Rule import/export works
- [ ] Old pages (Popular, Timeline, Collect, Info, Search) still accessible
- [ ] WebDAV sync works
- [ ] Bangumi sync works (if enabled)
- [ ] Danmaku works for anime
