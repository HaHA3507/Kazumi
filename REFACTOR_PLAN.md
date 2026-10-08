# REFACTOR_PLAN.md — Universal XPath Media Shell

> **Phase 1 Output**: Architecture analysis and refactoring plan for transforming Kazumi from an Anime-specific app into a Universal XPath Media Aggregation Player.

---

## Table of Contents

1. [当前架构](#1-当前架构)
2. [核心数据流](#2-核心数据流)
3. [Anime 强耦合点](#3-anime-强耦合点)
4. [可以复用的模块](#4-可以复用的模块)
5. [必须重构的模块](#5-必须重构的模块)
6. [可以删除的模块](#6-可以删除的模块)
7. [新的数据模型](#7-新的数据模型)
8. [新的 Rule Schema](#8-新的-rule-schema)
9. [UI 重构方案](#9-ui-重构方案)
10. [分阶段迁移方案](#10-分阶段迁移方案)
11. [每个阶段修改哪些文件](#11-每个阶段修改哪些文件)
12. [风险点](#12-风险点)
13. [兼容策略](#13-兼容策略)

---

## 1. 当前架构

### 1.1 技术栈

| 层 | 技术 | 说明 |
|---|---|---|
| 框架 | Flutter 3.47.6 | 跨平台 UI |
| 路由/DI | flutter_modular 7.1.0 | 声明式路由 + 依赖注入 |
| 状态管理 | MobX 2.6.0 | 响应式状态 (Observable/Action/Computed) |
| 本地存储 | Hive CE 2.16.0 | NoSQL key-value, 8 个 Box |
| 网络层 | Dio 5.11.0 | 5 个独立 Dio 实例 |
| 播放器 | media_kit (libmpv) | 硬件加速, HLS/MP4/DASH 自动检测 |
| XPath | xpath_selector 3.0.2 + html | HTML DOM 查询 |
| JSONPath | json_path 0.9.0 | API 模式 JSON 查询 |
| 弹幕 | canvas_danmaku 0.3.3 | 滚动弹幕渲染 |
| WebView | flutter_inappwebview + platform-specific | 无头 WebView 用于视频源解析 |

### 1.2 模块层次结构

```
main.dart
  └─ ModularApp(module: appModule)
       ├─ coreModule — 全局单例 (Repositories, Services, Controllers)
       └─ indexModule — 所有路由
            ├─ / (InitPage) — 启动加载页
            ├─ /onboarding — 首次引导
            ├─ /tab (IndexPage) — 4 Tab 主壳
            │    ├─ /tab/popular  — 推荐(Bangumi 热门/标签)
            │    ├─ /tab/timeline — 时间表(番剧放送日历)
            │    ├─ /tab/collect  — 追番(本地收藏库)
            │    └─ /tab/my       — 我的(统计+设置入口)
            ├─ /search — Bangumi 搜索 + 图片搜索(trace.moe)
            ├─ /info — 番剧详情(概览/吐槽/角色/关联/制作人员) + 规则搜索
            ├─ /video — 视频播放(剧集选择/弹幕/截图/同步播放)
            └─ /settings — 设置(播放/弹幕/规则/下载/同步/外观/网络/关于)
```

### 1.3 DI 模块划分

| 模块 | 作用域 | 注册的单例 |
|---|---|---|
| `coreModule` | 全 App | `CollectRepository`, `HistoryRepository`, `DownloadRepository`, `SearchHistoryRepository`, `CollectCrudRepository`, `DanmakuShieldRepository`, `DownloadManager`, `AudioController`, `PluginsController`, `CollectController`, `HistoryController`, `MyController`, `DownloadController`, `WebDav`, `HistoryPlaybackService`, `ShaderAssetService`, `DanmakuShieldSyncService` |
| `tabModule` | Tab 生命周期 | `PopularController`, `TimelineController` |
| 路由级 | 路由生命周期 | `SearchPageController`, `InfoController`, `VideoPageController`, `PlayerController` |

### 1.4 存储结构 (Hive CE)

| Box 名 | typeId | 模型 | 用途 |
|---|---|---|---|
| `favorites` | — | `BangumiItem` (0) | 旧收藏 (已废弃, 仅供迁移) |
| `collectibles` | — | `CollectedBangumi` (3) | 本地收藏 (想看/在看/看过/搁置/抛弃) |
| `histories` | — | `History` (1) + `Progress` (2) | 观看历史 (按 BangumiItem + 插件名) |
| `setting` | — | dynamic | 全部设置 (80+ 键) |
| `collectchanges` | — | `CollectedBangumiChange` (5) | 收藏变更日志 (WebDAV 同步) |
| `shieldList` | — | String | 弹幕屏蔽词 |
| `searchHistory` | — | `SearchHistory` (6) | 搜索关键词历史 |
| `downloads` | — | `DownloadRecord` (7) + `DownloadEpisode` (8) | 下载记录 |

**规则存储**: 不在 Hive 中。存储在 `getApplicationSupportDirectory()/plugins/v2/plugins.json` (单个 JSON 文件, 由 `PluginsController` 管理)。

### 1.5 网络层架构

```
DioFactory (单例)
  ├─ apiDio       — 通用 API (DanDanPlay, trace.moe)
  ├─ bangumiDio   — Bangumi API (ECH 加速拦截器 + ECH 适配器)
  ├─ rulesRepoDio — 规则仓库 (GitHub 镜像拦截器)
  ├─ pluginDio    — 规则目标网站 (随机 UA + 随机 Accept-Language)
  └─ downloadDio  — 下载 (更长超时)
```

### 1.6 代码规模统计

| 目录 | 文件数 | 主要职责 |
|---|---|---|
| `lib/plugins/` | 5 | 规则模型 (Plugin, ApiConfig, AntiCrawler) |
| `lib/services/plugin/` | 8 | 规则引擎 (RuleEngine, XPath/API 策略, 搜索服务, 导入解析, 验证码, Cookie) |
| `lib/services/video_source/` | 5 | 视频源解析 (WebView 解析, 格式枚举, 解析池) |
| `lib/services/player/` | 12 | 播放器服务 (音频, PiP, 截图, 同步播放, 外部播放器, 缓存, 关机) |
| `lib/modules/` | ~30 | 领域模型 (Bangumi, Collect, History, Search, Download, Danmaku, Roads, Characters, Staff, Comments) |
| `lib/repositories/` | 6 | 数据仓储 (History, Collect, Download, SearchHistory, DanmakuShield) |
| `lib/request/` | ~15 | 网络层 (Dio 工厂, 拦截器, API 客户端, 端点常量) |
| `lib/pages/` | ~80 | UI 页面 (Popular, Timeline, Collect, My, Search, Info, Video, Player, Settings, PluginEditor, Onboarding, History, Download, About) |
| `lib/bean/` | ~25 | UI 组件 (卡片, 对话框, Widget, 设置项) |
| `lib/webview/` | 10 | WebView 控制器 (视频解析 + 验证码, 各平台实现) |
| `lib/utils/` | ~20 | 工具 (URL 规范化, M3U8 解析, 编码, 加密, 格式化, 常量) |
| `lib/services/` | ~25 | 服务 (网络, 平台, 存储, 同步, 更新, 日志) |
| **总计** | ~240 | |

---

## 2. 核心数据流

### 2.1 当前完整数据流 (从搜索到播放)

```
用户输入关键词
    │
    ▼
SearchPageController.searchBangumi()          ← ❶ Bangumi API 搜索
    │  BangumiApi.bangumiSearch(keyword)
    │  → DioFactory.bangumiDio (ECH/镜像加速)
    ▼
ObservableList<BangumiItem>                     ← ❷ Bangumi 搜索结果
    │  (name, nameCn, summary, images, tags, rank, rating...)
    │
    ▼  用户点击某条结果
context.pushNamed('/info/', arguments: bangumiItem)
    │
    ▼
InfoPage → InfoController
    │  queryBangumiInfoByID(id)                  ← ❸ Bangumi 详情
    │  queryBangumiCommentsByID(id)              ← Bangumi 吐槽
    │  queryBangumiCharactersByID(id)            ← Bangumi 角色
    │  queryBangumiStaffsByID(id)                ← Bangumi 制作人员
    │  queryBangumiRelationsByID(id)             ← Bangumi 关联作品
    ▼
InfoPage 显示 5 个 Tab (概览/吐槽/角色/关联/制作人员)
    │
    │  用户点击 "视频资源" 按钮
    ▼
SourceSheet (source_sheet.dart)
    │  创建 PluginSearchService
    │  queryAllSource(keyword)                   ← ❹ 规则引擎并发搜索
    │  → 对每个 Plugin 并发调用:
    │
    ├─ Plugin.queryBangumi(keyword)              ← ❺ 单规则搜索
    │   │  → RuleEngine.search(keyword)
    │   │
    │   ├─[XPath] → XPathRuleStrategy.prepareSearchRequest()
    │   │            searchURL.replaceAll('@keyword', encoded)
    │   │            GET or POST (usePost)
    │   │
    │   └─[API]  → ApiRuleStrategy.prepareRequest({keyword})
    │                _renderTemplate(url, @keyword)
    │
    │   ▼  HTTP 请求 (PluginSiteClient → DioFactory.pluginDio)
    │   ▼  响应解析
    │   ├─[XPath] → HTML → queryXPath(searchList) → 逐节点提取
    │   │            name = searchName XPath, href = searchResult XPath
    │   │
    │   └─[API]  → JSON → RestrictedJsonPath.read(listPath)
    │                name = namePath, source = sourcePath
    │
    │   ▼  验证码检测 (如果反爬配置启用)
    │   ▼  CaptchaRequiredException → 验证码 WebView 流程
    │   ▼
    │  PluginSearchResponse [SearchItem(name, src)]
    │
    ▼  用户点击某个搜索结果
SourceSheet._openSearchItem(searchItem)
    │  plugin.queryChapterRoads(searchItem.src)  ← ❻ 规则引擎获取剧集
    │  → RuleEngine.queryChapters(source)
    │
    │   ├─[XPath] → normalizeEpisodeUrl(baseUrl, source) → GET
    │   │            queryXPath(chapterRoads) → 逐路: queryXPath(chapterResult)
    │   │            href → episodeUrl, text → episodeName
    │   │            Road(name="播放线路N", data=[urls], identifier=[names])
    │   │
    │   └─[API]  → _parseNested() or _parseDelimited()
    │                → _resolveEpisodeUrl() (episodePage 模板渲染)
    │                → Road(name, data=[pageUrls], identifier=[names])
    │
    ▼
OnlineVideoPlaybackArgs(plugin, bangumiItem, title, src, roads)
    │
    ▼
context.pushNamed('/video/', arguments: args)
    │
    ▼
VideoPage → VideoPageController
    │  changeEpisode(episode, road)               ← ❼ 选择剧集
    │  _resolveOnlineEpisode()
    │  pageUrl = roadList[road].data[index]
    │  normalizeEpisodeUrl(baseUrl, pageUrl)
    │
    ▼  视频源解析
_resolveWithVideoSourceService()
    │  WebViewVideoSourceService.resolve(pageUrl)
    │  → VideoWebviewController.loadUrl()          ← ❽ WebView 加载页面
    │  → 注入 JS (blob parser / video tag parser / iframe scanner)
    │  → 拦截网络请求 / DOM 变化
    │  → 检测 m3u8/mp4 URL
    │  → VideoParserEvent(url, offset, format)
    │
    ▼
VideoSource(url, format)
    │
    ▼  播放器初始化
PlayerController.init(PlaybackInitParams(
      videoUrl: source.url,
      httpHeaders: {user-agent: plugin.userAgent, referer: plugin.referer},
      bangumiId: bangumiItem.id,
      pluginName: plugin.name,
      episode: index,
      adBlockerEnabled: plugin.adBlocker,
      ...
    ))
    │
    ▼
PlayerPlaybackController.createVideoController()
    │  media_kit Player + VideoController
    │  MPV 属性: 缓存, 硬解, 代理, 音频, 超分辨率(Anime4K)
    │  player.open(Media(videoUrl, httpHeaders: httpHeaders))
    │
    ▼
播放中...
    │
    ├─ 弹幕加载: DanDanPlay API (BangumiID → DanDanID → danmaku)
    ├─ 历史记录: HistoryRepository.updateHistory(bangumiItem, plugin, episode, progress)
    ├─ 音频会话: AudioController (通知栏/锁屏控制)
    └─ PiP / 全屏 / 横屏 / 后台播放
```

### 2.2 关键数据模型关系

```
BangumiItem (核心, 贯穿全 App)
    │
    ├──→ InfoPage (详情展示)
    │      ├── comments ← BangumiApi
    │      ├── characters ← BangumiApi
    │      ├── staff ← BangumiApi
    │      └── relations ← BangumiApi
    │
    ├──→ SourceSheet (规则搜索)
    │      └── PluginSearchResponse [SearchItem(name, src)]
    │             └── Road(name, data[urls], identifier[names])
    │
    ├──→ VideoPage
    │      └── VideoPlaybackArgs(bangumiItem, plugin, roads)
    │             └── EpisodeRef(listIndex, pageUrl, sortNumber, ...)
    │
    ├──→ History (bangumiItem 嵌入)
    │      └── Progress(episode, road, milliseconds)
    │
    ├──→ CollectedBangumi (bangumiItem 嵌入)
    │      └── CollectType (watching/planToWatch/...)
    │
    ├──→ DownloadRecord (bangumiId, bangumiName, bangumiCover)
    │      └── DownloadEpisode(episodeNumber, road, m3u8Url, ...)
    │
    └──→ Danmaku (via bangumiId → DanDanPlay API)
```

---

## 3. Anime 强耦合点

### 3.1 领域模型层 (`lib/modules/`)

| 文件 | 耦合点 | 严重度 | 说明 |
|---|---|---|---|
| `bangumi/bangumi_item.dart` | `BangumiItem` 是全 App 核心模型 | **致命** | 嵌入到 History, CollectedBangumi, DownloadRecord, VideoPlaybackArgs 中; 字段 airWeekday, votesCount 等纯动漫字段 |
| `bangumi/bangumi_relation.dart` | `selectRelatedAnime()` 过滤 `type==2` (动漫) | 高 | BFS 遍历前传/续集链, 动漫专属逻辑 |
| `bangumi/bangumi_collection.dart` | `toBangumiItem()` 硬编码 `type: 2` | 中 | Bangumi API 收藏模型, 仅动漫 |
| `bangumi/bangumi_interest.dart` | 用户在 Bangumi 上的收藏状态 | 中 | 与 Bangumi 同步绑定的用户兴趣 |
| `bangumi/bangumi_collection_type.dart` | 枚举: 想看/看过/在看/搁置/抛弃 | 中 | 动漫收藏分类法 |
| `bangumi/episode_item.dart` | `EpisodeInfo` type: 0=ep, 1=sp, 2=op, 3=ed | 中 | 动漫剧集类型分类 |
| `collect/collect_module.dart` | `CollectedBangumi` 嵌入 `BangumiItem` | **致命** | 收藏模型完全绑定 Bangumi |
| `collect/collect_change_module.dart` | `CollectedBangumiChange` 使用 `bangumiID` | 高 | 变更日志以 Bangumi ID 为键 |
| `collect/collect_type.dart` | `CollectType` 想看/看过/在看/搁置/抛弃 | 中 | 动漫收藏分类 |
| `history/history_module.dart` | `History` 嵌入 `BangumiItem`, 键含 bangumiId | **致命** | 历史记录以 BangumiItem 为核心 |
| `download/download_module.dart` | `DownloadRecord` 含 `bangumiId`, `bangumiName`, `bangumiCover` | 高 | 下载记录绑定 Bangumi |
| `roads/road_module.dart` | `Road` — 通用但命名 "播放线路N" | 低 | 数据结构通用, 默认命名中文动漫风 |
| `search/plugin_search_module.dart` | `SearchItem(name, src)` — 通用 | 低 | 结构通用, 无动漫耦合 |
| `search/image_search_module.dart` | `ImageSearchItem` → Anilist 动漫元数据 | 高 | trace.moe 动漫图片搜索, 完全动漫专属 |
| `danmaku/*` | DanDanPlay API (动漫弹幕服务) | 高 | 弹幕系统完全依赖动漫 ID 映射 |

### 3.2 UI 页面层 (`lib/pages/`)

| 页面 | 耦合点 | 严重度 | 说明 |
|---|---|---|---|
| `popular/` | Bangumi 热门番组 + `defaultAnimeTags` | **致命** | 整个页面是 Bangumi 动漫推荐 |
| `timeline/` | Bangumi 番剧放送日历, 7 天 × 季度 | **致命** | 整个页面是动漫放送时间表 |
| `collect/` | 标题 "追番", 展示 `BangumiItem` 卡片 | **致命** | 收藏库以 Bangumi 为核心 |
| `search/` | 搜索调 `BangumiApi.bangumiSearch()` | **致命** | 搜索完全依赖 Bangumi API |
| `search/image_search_page.dart` | trace.moe 动漫以图搜图 | 高 | 动漫专属功能 |
| `info/` | 5 个 Tab (概览/吐槽/角色/关联/制作人员) 全部来自 Bangumi | **致命** | 详情页完全依赖 Bangumi 元数据 |
| `info/source_sheet.dart` | 搜索关键词来自 `bangumiItem.nameCn` | 高 | 规则搜索以 Bangumi 名称为关键词 |
| `info/info_controller.dart` | 所有查询基于 Bangumi API | 高 | 控制器完全绑定 Bangumi |
| `video/video_playback_args.dart` | `VideoPlaybackArgs` 强制包含 `bangumiItem` | **致命** | 播放参数必须携带 BangumiItem |
| `video/video_controller.dart` | 弹幕加载用 `bangumiId`, 历史记录用 `bangumiItem` | 高 | 播放控制器绑定 Bangumi |
| `my/my_space_view.dart` | 观看统计以 Bangumi 为单位 | 中 | 统计逻辑嵌入 Bangumi |
| `settings/sync/bangumi_sync_page.dart` | Bangumi 同步设置 | 中 | Bangumi 专属同步 |
| `onboarding/steps/mirror_settings_step.dart` | Bangumi 镜像设置引导 | 低 | 引导流程含 Bangumi 配置 |

### 3.3 服务层 (`lib/services/`)

| 文件 | 耦合点 | 严重度 |
|---|---|---|
| `player/controller/player_super_resolution.dart` | Anime4K GLSL 着色器 | 中 |
| `player/controller/player_danmaku_controller.dart` | DanDanPlay API (Bangumi ID → DanDan ID) | 高 |
| `sync/bangumi_sync_service.dart` | Bangumi 收藏同步 | 高 |
| `network/bangumi_acceleration.dart` | Bangumi ECH/镜像加速 | 中 |
| `network/bangumi_ech_resolver.dart` | Bangumi ECH DNS 解析 | 中 |
| `network/bangumi_ech_image_service.dart` | Bangumi 图片 ECH 加载 | 中 |
| `network/bangumi_image_url_rewriter.dart` | Bangumi 图片 URL 重写 | 中 |

### 3.4 网络层 (`lib/request/`)

| 文件 | 耦合点 | 严重度 |
|---|---|---|
| `apis/bangumi_api.dart` (770 行) | 全部 Bangumi 业务逻辑 | **致命** |
| `apis/danmaku_api.dart` | DanDanPlay 弹幕 API | 高 |
| `apis/trace_api.dart` | trace.moe 以图搜图 | 高 |
| `clients/bangumi_client.dart` | Bangumi OAuth + 镜像签名 | 高 |
| `clients/danmaku_client.dart` | DanDanPlay HMAC 签名 | 高 |
| `core/bangumi_transport.dart` | ECH 适配器 | 中 |
| `config/api_endpoints.dart` | 大量 Bangumi/DanDan/trace 端点 | 中 |

### 3.5 工具层 (`lib/utils/`)

| 文件 | 耦合点 | 严重度 |
|---|---|---|
| `anime_season.dart` | 动漫季度计算 | 中 |
| `search_parser.dart` | Bangumi 搜索 DSL (season:2024Q1, weekday:1,3, tag:) | 高 |
| `dandan_credentials.dart` | DanDanPlay 凭证 | 低 |
| `bangumi_mirror_credentials.dart` | Bangumi 镜像凭证 | 低 |

### 3.6 耦合总结

```
致命耦合 (阻断通用化):
  ┌──────────────────────────────────────────────────┐
  │  BangumiItem 是全 App 唯一的"内容"领域模型        │
  │  所有数据流: 搜索→详情→播放→历史→收藏→下载         │
  │  全部以 BangumiItem 为核心传递                      │
  └──────────────────────────────────────────────────┘

高耦合 (需要重构):
  ┌──────────────────────────────────────────────────┐
  │  搜索: 直接调 BangumiApi, 而非调规则引擎           │
  │  详情: 完全依赖 Bangumi 元数据                      │
  │  弹幕: 依赖 DanDanPlay (动漫弹幕)                  │
  │  日历/推荐: 完全是 Bangumi 番组功能                 │
  │  同步: Bangumi 收藏同步                            │
  └──────────────────────────────────────────────────┘

中/低耦合 (可适配或可选保留):
  ┌──────────────────────────────────────────────────┐
  │  超分辨率: Anime4K 着色器 (可作为可选插件)          │
  │  规则引擎: 默认命名 "播放线路N", "第N集" (可配置)  │
  │  网络加速: Bangumi ECH (可保留为可选模块)          │
  └──────────────────────────────────────────────────┘
```

---

## 4. 可以复用的模块

### 4.1 完全可复用 (无需修改)

| 模块 | 文件 | 说明 |
|---|---|---|
| **Rule Engine 核心** | `lib/services/plugin/rule_engine.dart` | 搜索/章节请求执行 + 响应解析, 引擎本身与内容类型无关 |
| **XPath 策略** | `lib/services/plugin/xpath_rule_strategy.dart` | HTML → XPath → 提取, 通用 |
| **API 策略** | `lib/services/plugin/api_rule_strategy.dart` | JSON → JSONPath → 提取, 通用 |
| **Rule Engine 模型** | `lib/services/plugin/rule_engine_models.dart` | `PreparedRuleRequest`, `RuleSearchTrace` 等, 通用 |
| **验证码服务** | `lib/services/plugin/captcha_verification_service.dart` | 三种验证码流程, 通用 |
| **Cookie 管理** | `lib/services/plugin/plugin_cookie_manager.dart` | 按规则的 Cookie 管理, 通用 |
| **规则导入解析** | `lib/services/plugin/plugin_import_parser.dart` | `kazumi://` 链接/JSON 导入, 通用 |
| **规则搜索服务** | `lib/services/plugin/plugin_search_service.dart` | 并发多规则搜索, 通用 |
| **URL 规范化** | `lib/utils/episode_url.dart` | `normalizeEpisodeUrl()`, 通用 |
| **M3U8 解析器** | `lib/utils/m3u8_parser.dart` | HLS 播放列表解析, 通用 |
| **M3U8 广告过滤** | `lib/utils/m3u8_ad_filter.dart` | HLS 广告段过滤, 通用 |
| **HTTP 头工具** | `lib/utils/http_headers.dart` | 随机 UA, 通用 |
| **编码工具** | `lib/utils/encoding.dart` | Base64 编解码, 通用 |
| **加密工具** | `lib/utils/crypto.dart` | HMAC 签名, 通用 |
| **DioFactory** | `lib/request/core/dio_factory.dart` | 多 Dio 实例工厂, 通用 |
| **NetworkConfig** | `lib/request/core/network_config.dart` | 网络配置, 通用 |
| **NetworkException** | `lib/request/core/network_exception.dart` | 类型化异常, 通用 |
| **NetworkErrorMapper** | `lib/request/core/network_error_mapper.dart` | 异常映射, 通用 |
| **PluginSiteClient** | `lib/request/clients/plugin_site_client.dart` | 规则目标网站 HTTP, 通用 |
| **DownloadHttpClient** | `lib/request/clients/download_http_client.dart` | 下载客户端, 通用 |
| **WebView 视频源解析** | `lib/services/video_source/webview_video_source_service.dart` | WebView 解析 m3u8/mp4, 通用 |
| **WebView 视频源接口** | `lib/services/video_source/video_source_service.dart` | `IVideoSourceService`, `VideoSource`, 通用 |
| **视频源格式枚举** | `lib/services/video_source/video_source_format.dart` | `auto`/`hls`, 通用 |
| **视频源解析池** | `lib/services/video_source/video_source_resolver_pool.dart` | 并行解析池, 通用 |
| **WebView 控制器** | `lib/webview/video/*` | 各平台 WebView 实现, 通用 |
| **验证码 WebView** | `lib/webview/captcha/*` | 各平台验证码 WebView, 通用 |
| **media_kit 播放器** | `lib/pages/player/*` | 播放器核心, 只接受 URL+Headers, 通用 |
| **播放器面板** | `lib/pages/player/player_item.dart` 等 | 播放控制 UI, 通用 |
| **播放器传输栏** | `lib/pages/player/player_transport_bar.dart` | 进度条/播放控制, 通用 |
| **音频控制器** | `lib/services/player/audio_controller.dart` | 通知栏/锁屏控制, 通用 |
| **PiP 工具** | `lib/services/player/pip_utils.dart` | 画中画, 通用 |
| **播放缓存策略** | `lib/services/player/playback_cache_policy.dart` | 缓存配置, 通用 |
| **外部播放器** | `lib/services/player/external_playback_launcher.dart` | 外部播放器启动, 通用 |
| **代理系统** | `lib/services/network/proxy_*.dart`, `system_proxy_service.dart` | 代理管理, 通用 |
| **存储框架** | `lib/services/storage/storage.dart`, `settings_keys.dart` | Hive 管理 + 设置键, 通用 |
| **图片缓存** | `lib/services/storage/image_cache_service.dart` | 图片缓存, 通用 |
| **同步播放** | `lib/services/player/syncplay_*.dart` | SyncPlay, 通用 |
| **日志** | `lib/services/logging/logger.dart` | 日志, 通用 |
| **下载管理器** | `lib/services/download/download_manager.dart` | HLS 下载, 通用 (需解耦 Bangumi) |
| **后台下载** | `lib/services/download/background_download_service.dart` | 后台下载, 通用 |
| **异步工具** | `lib/utils/async_*.dart` | 限流/队列/单飞, 通用 |
| **格式化工具** | `lib/utils/format.dart`, `date_time.dart` | 格式化, 通用 |
| **设备工具** | `lib/utils/device.dart` | 设备信息, 通用 |
| **文件系统** | `lib/utils/file_system.dart` | 文件操作, 通用 |

### 4.2 可复用但需小改

| 模块 | 文件 | 需要的修改 |
|---|---|---|
| **Road 模型** | `lib/modules/roads/road_module.dart` | 默认命名从 "播放线路N" 改为可配置 |
| **SearchItem** | `lib/modules/search/plugin_search_module.dart` | 可增加 cover/description 字段 |
| **PlaybackInitParams** | `lib/pages/player/controller/player_models.dart` | `bangumiId` → `mediaId` (string), 增加灵活性 |
| **Plugin 模型** | `lib/plugins/plugins.dart` | `type` 默认值从 "anime" 改为 "video"; 增加可选字段 |
| **PluginsController** | `lib/plugins/plugins_controller.dart` | 增加 enable/disable, priority 字段; 保持存储格式 |
| **规则编辑器** | `lib/pages/plugin_editor/*` | 扩展支持新 Schema 字段; 保持现有编辑能力 |
| **规则测试器** | `lib/pages/plugin_editor/plugin_test_page.dart` | 扩展支持新 Schema 测试 |
| **规则管理 UI** | `lib/pages/plugin_editor/rule_management_widgets.dart` | 增加 enable/disable 开关 |
| **历史同步** | `lib/services/sync/history_sync_service.dart` | 解耦 BangumiItem → MediaItem JSON 编解码 |
| **WebDAV** | `lib/services/sync/webdav.dart` | 通用, 无需修改 |
| **收藏同步合并** | `lib/modules/collect/collect_sync_merger.dart` | 解耦 BangumiItem → MediaItem |
| **历史模型** | `lib/modules/history/history_module.dart` | `bangumiItem` 字段 → `mediaItem` (新模型), 保持 Hive typeId 兼容 |
| **搜索历史** | `lib/modules/search/search_history_module.dart` | 通用, 无需修改 |

---

## 5. 必须重构的模块

### 5.1 领域模型重构

| 模块 | 当前 | 目标 | 优先级 |
|---|---|---|---|
| 内容模型 | `BangumiItem` (int id, anime 字段) | `MediaItem` (string id, 通用字段 + metadata map) | P0 |
| 收藏模型 | `CollectedBangumi` (嵌入 BangumiItem) | `CollectedMedia` (嵌入 MediaItem) | P0 |
| 历史模型 | `History` (嵌入 BangumiItem) | `History` (嵌入 MediaItem) | P0 |
| 下载模型 | `DownloadRecord` (bangumiId/name/cover) | `DownloadRecord` (mediaId/title/cover) | P1 |
| 播放参数 | `VideoPlaybackArgs` (必须含 bangumiItem) | `MediaPlaybackArgs` (含 MediaItem) | P0 |
| 规则模型 | `Plugin` (type="anime") | `MediaRule` (type 可选, 默认 "video") | P1 |
| 剧集模型 | 无独立模型 (Road.data=urls, identifier=names) | `MediaEpisode` (id, title, url, group?) | P1 |

### 5.2 搜索流程重构

| 模块 | 当前 | 目标 |
|---|---|---|
| 搜索页面 | `SearchPageController.searchBangumi()` 调 Bangumi API | `SearchController.search()` 并发调所有启用规则的 Rule Engine |
| 搜索结果 | `ObservableList<BangumiItem>` | `ObservableList<MediaItem>` (来自多规则, 去重后) |
| 搜索 DSL | `SearchParser` (season/weekday/tag/rank/score — Bangumi 专属) | 移除或改为可选过滤 |
| 搜索历史 | 通用, 可复用 | 保持 |

### 5.3 详情流程重构

| 模块 | 当前 | 目标 |
|---|---|---|
| 详情页 | 5 Tab (概览/吐槽/角色/关联/制作人员) 全来自 Bangumi | 简化为: 概览 + 剧集列表 + 来源列表; Bangumi 元数据改为可选增强 |
| 详情控制器 | `InfoController` 完全依赖 Bangumi API | `DetailController` 优先从规则获取详情, Bangumi 作为可选元数据源 |
| 来源选择 | `SourceSheet` 以 `bangumiItem.nameCn` 为关键词 | `SourceSheet` 以 `MediaItem.title` 为关键词, 支持别名 |

### 5.4 播放流程重构

| 模块 | 当前 | 目标 |
|---|---|---|
| 播放参数 | `PlaybackInitParams` 含 `bangumiId` (int) | `PlaybackInitParams` 含 `mediaId` (String) |
| 弹幕 | DanDanPlay API (需要 Bangumi ID → DanDan ID) | 弹幕改为可选/可配置源; 保留 DanDanPlay 作为可选弹幕提供者 |
| 历史 | `HistoryRepository` 以 BangumiItem 为键 | 以 MediaItem 为键 (string id) |
| 超分辨率 | Anime4K 着色器 (动漫专属) | 保留但改为可选, 默认关闭; 可扩展其他着色器 |

### 5.5 导航重构

| 模块 | 当前 | 目标 |
|---|---|---|
| 主 Tab | 推荐 / 时间表 / 追番 / 我的 | 首页 / 搜索 / 媒体库 / 历史 / 设置 |
| 首页 | PopularController (Bangumi 热门) | HomeController (最近观看 + 收藏 + 规则入口) |
| 时间表 | TimelineController (Bangumi 日历) | **删除** |
| 收藏 | CollectPage (标题"追番", 展示 BangumiItem) | LibraryPage (展示 MediaItem, 通用收藏) |

### 5.6 规则引擎扩展

| 模块 | 当前 | 目标 |
|---|---|---|
| Rule Schema | v8, 仅 search + chapter, 无 detail/cover/description | v9, 增加 detail/cover/description/pagination/stream 支持 |
| 变量 | `@keyword`, `@source`, `@episodeUrl`, `@roadIndex/Number`, `@episodeIndex/Number` | 增加 `{page}`, `{url}`, `{episode_url}` 等 |
| 分页 | 不支持 | 支持搜索分页 (page 变量 + 翻页规则) |
| 流解析 | 仅 WebView (JS 注入) | 增加 XPath 流解析 (规则直接指定 stream xpath) |
| 剧集分组 | Road (线性列表) | 支持 group/season 分组 |

---

## 6. 可以删除的模块

> **原则**: 不直接删除, 先标记为 deprecated, 确认无依赖后移除。Bangumi 相关功能改为可选模块。

### 6.1 可以移除的页面

| 页面 | 文件 | 原因 | 替代方案 |
|---|---|---|---|
| Popular | `lib/pages/popular/*` | Bangumi 热门番组, 动漫专属 | 替换为通用首页 (最近观看 + 收藏 + 规则) |
| Timeline | `lib/pages/timeline/*` | Bangumi 番剧放送日历, 动漫专属 | 删除, 或作为可选插件 |
| Image Search | `lib/pages/search/image_search_*` | trace.moe 动漫以图搜图 | 删除 |
| Character/Staff | `lib/pages/info/character_*.dart`, `info_comments_*` | Bangumi 角色/制作人员 | 删除或作为可选 Tab |
| Bangumi Sync | `lib/pages/settings/sync/bangumi_sync_page.dart` | Bangumi 收藏同步 | 改为可选同步源 |

### 6.2 可以移除的服务

| 服务 | 文件 | 原因 |
|---|---|---|
| Bangumi API | `lib/request/apis/bangumi_api.dart` | 动漫元数据 API, 通用 App 不需要 |
| Bangumi Client | `lib/request/clients/bangumi_client.dart` | OAuth + 镜像签名 |
| Bangumi Transport | `lib/request/core/bangumi_transport.dart` | ECH 适配器 |
| Bangumi 加速 | `lib/services/network/bangumi_acceleration.dart` | ECH/镜像 |
| Bangumi ECH Resolver | `lib/services/network/bangumi_ech_resolver.dart` | DoH + ECH |
| Bangumi ECH Image | `lib/services/network/bangumi_ech_image_service.dart` | 图片 ECH |
| Bangumi Image Rewriter | `lib/services/network/bangumi_image_url_rewriter.dart` | 图片 URL 重写 |
| Bangumi Sync Service | `lib/services/sync/bangumi_sync_service.dart` | 收藏同步 |
| trace.moe API | `lib/request/apis/trace_api.dart` | 动漫以图搜图 |
| Trace Client | `lib/request/clients/trace_client.dart` | trace.moe HTTP |
| Anime Season | `lib/utils/anime_season.dart` | 动漫季度计算 |
| Search Parser | `lib/utils/search_parser.dart` | Bangumi 搜索 DSL |
| Bangumi Mirror Credentials | `lib/utils/bangumi_mirror_credentials.dart` | 镜像凭证 |
| Dandan Credentials | `lib/utils/dandan_credentials.dart` | 弹幕凭证 |

### 6.3 可以移除的领域模型

| 模型 | 文件 | 原因 |
|---|---|---|
| `BangumiItem` | `lib/modules/bangumi/bangumi_item.dart` | 替换为 `MediaItem` (迁移后可删) |
| `BangumiTag` | `lib/modules/bangumi/bangumi_tag.dart` | 动漫标签 |
| `BangumiRelation` | `lib/modules/bangumi/bangumi_relation.dart` | 动漫关联 (BFS 前传/续集) |
| `BangumiCollection` | `lib/modules/bangumi/bangumi_collection.dart` | Bangumi API 收藏 |
| `BangumiInterest` | `lib/modules/bangumi/bangumi_interest.dart` | Bangumi 用户兴趣 |
| `BangumiReview` | `lib/modules/bangumi/bangumi_review.dart` | Bangumi 评价 |
| `BangumiCollectionType` | `lib/modules/bangumi/bangumi_collection_type.dart` | Bangumi 收藏枚举 |
| `BangumiSyncPriority` | `lib/modules/bangumi/sync_priority.dart` | Bangumi 同步优先级 |
| `EpisodeInfo` | `lib/modules/bangumi/episode_item.dart` | Bangumi 剧集 (type: ep/sp/op/ed) |
| `CharacterItem` | `lib/modules/characters/*` | 角色模型 |
| `StaffFullItem` | `lib/modules/staff/*` | 制作人员模型 |
| `CommentItem` | `lib/modules/comments/*` | Bangumi 吐槽 |
| `ImageSearchItem` | `lib/modules/search/image_search_module.dart` | trace.moe 搜索结果 |
| `CollectedBangumi` | `lib/modules/collect/collect_module.dart` | 替换为 `CollectedMedia` |
| `CollectedBangumiChange` | `lib/modules/collect/collect_change_module.dart` | 替换为 `CollectedMediaChange` |
| `CollectType` | `lib/modules/collect/collect_type.dart` | 重新设计通用收藏类型 |
| `CollectSyncMerger` | `lib/modules/collect/collect_sync_merger.dart` | 适配新模型 |
| `CollectSyncPlan` | `lib/modules/collect/collect_sync_plan.dart` | 适配新模型 |
| `WatchStats` | `lib/modules/my/watch_stats.dart` | 适配新模型 |
| `DanmakuEntry` 等 | `lib/modules/danmaku/*` | 弹幕改为可选模块 |
| `BangumiRelation` 遍历 | `lib/modules/bangumi/bangumi_relation.dart` | 动漫关联链 |

### 6.4 可以移除的 UI 组件

| 组件 | 文件 | 原因 |
|---|---|---|
| `BangumiCardV` | `lib/bean/card/bangumi_card.dart` | 动漫卡片 |
| `BangumiInfoCard` | `lib/bean/card/bangumi_info_card.dart` | 动漫信息卡 |
| `BangumiTimelineCard` | `lib/bean/card/bangumi_timeline_card.dart` | 时间表卡片 |
| `BangumiAvatar` | `lib/bean/widget/bangumi_avatar.dart` | 动漫头像 |
| `BangumiMirrorErrorWidget` | `lib/bean/widget/bangumi_mirror_error_widget.dart` | 镜像错误 |
| `CharacterCard` | `lib/bean/card/character_card.dart` | 角色卡 |
| `StaffCard` | `lib/bean/card/staff_card.dart` | 制作人员卡 |
| `CommentsCard` | `lib/bean/card/comments_card.dart` | 吐槽卡 |
| `UserCommentsCard` | `lib/bean/card/user_comments_card.dart` | 用户吐槽卡 |
| `PaletteCard` | `lib/bean/card/palette_card.dart` | 动漫色调卡 |
| BBCode | `lib/bbcode/*` | Bangumi BBCode 渲染 |

> **注意**: 上述"可以删除"是指在完成迁移后的最终状态。在迁移过程中, 这些模块应保持可用, 通过 Adapter 桥接。

---

## 7. 新的数据模型

### 7.1 MediaItem (通用内容项)

```dart
/// 通用媒体项 — 搜索结果、收藏、历史的基本单元
class MediaItem {
  /// 唯一标识: "${sourceId}:${id}" 或规则定义的 ID
  final String id;

  /// 标题 (显示用)
  final String title;

  /// 原始标题 (可选, 如日文原名)
  final String? originalTitle;

  /// 封面 URL
  final String? cover;

  /// 描述/简介
  final String? description;

  /// 年份
  final String? year;

  /// 类型/分类 (如 "movie", "tv", "anime", "variety")
  final String? genre;

  /// 详情页 URL (用于规则引擎获取剧集)
  final String? detailUrl;

  /// 来源规则 ID
  final String sourceId;

  /// 媒体类型
  final MediaType type;

  /// 扩展元数据 (规则可自定义)
  final Map<String, dynamic>? metadata;
}

enum MediaType {
  movie,       // 电影
  tv,          // 电视剧
  anime,       // 动漫
  variety,     // 综艺
  documentary, // 纪录片
  sports,      // 体育
  mv,          // MV
  video,       // 通用视频
  other,       // 其他
  unknown,     // 未知 (规则未指定类型时)
}
```

### 7.2 MediaDetail (详情)

```dart
/// 媒体详情 — 从详情页 URL 获取的完整信息
class MediaDetail {
  final String id;
  final String title;
  final String? originalTitle;
  final String? cover;
  final String? description;
  final String? year;
  final String? genre;
  final String? rating;
  final String? tags;
  final String sourceId;
  final MediaType type;
  final Map<String, dynamic>? metadata;

  /// 剧集列表 (可能有多组/多季)
  final List<MediaEpisodeGroup> episodeGroups;
}

/// 剧集分组 (如 "第一季", "线路1", "Main")
class MediaEpisodeGroup {
  final String id;
  final String title;
  final List<MediaEpisode> episodes;
}

/// 单集
class MediaEpisode {
  final String id;
  final String title;
  final String url;       // 播放页 URL
  final String? thumbnail;
  final String sourceId;
  final String? group;    // 所属分组 ID
}
```

### 7.3 MediaStream (播放流)

```dart
/// 播放流 — 从播放页 URL 解析出的可播放地址
class MediaStream {
  final String url;

  /// 流质量标签 (如 "1080p", "720p", "高清")
  final String? quality;

  /// 流格式 (mp4, hls, dash, auto)
  final String? format;

  /// HTTP 请求头
  final Map<String, String>? headers;

  /// Referer
  final String? referer;

  /// User-Agent
  final String? userAgent;

  /// 是否直播流
  final bool isLive;
}
```

### 7.4 MediaSource (内容源)

```dart
/// 内容源 — 一个已安装的规则及其状态
class MediaSource {
  final String id;
  final String name;
  final String? baseUrl;
  final bool enabled;
  final int priority;      // 排序优先级
  final DateTime? installedAt;
  final DateTime? updatedAt;
  final String version;
}
```

### 7.5 MediaRule (规则)

```dart
/// 规则 — 描述如何从某网站搜索、解析详情、解析剧集、解析流
class MediaRule {
  final String version;    // Schema 版本
  final String id;         // 规则 ID
  final String name;       // 规则名称
  final String? baseUrl;
  final String? type;      // 内容类型提示 (可选)

  final RuleSearch? search;
  final RuleDetail? detail;
  final RuleEpisodes? episodes;
  final RuleStream? stream;

  final RuleHeaders? headers;
  final RuleAntiCrawler? antiCrawler;

  // 旧 Kazumi 规则兼容字段 (legacy)
  final bool usePost;
  final bool useLegacyParser;
  final bool adBlocker;
  final String? userAgent;
  final String? referer;
  final String? searchURL;
  final String? searchList;
  final String? searchName;
  final String? searchResult;
  final String? chapterRoads;
  final String? chapterResult;
  final String? searchMode;
  final String? chapterMode;
  final ApiSearchConfig? searchApiConfig;
  final ApiChapterConfig? chapterApiConfig;
}
```

### 7.6 与旧模型的映射

```
BangumiItem          → MediaItem
  id (int)             → id (string: "bangumi:${id}" 或规则定义)
  name/nameCn          → title / originalTitle
  summary              → description
  images['large']      → cover
  airDate              → year
  type (2=anime)       → type (MediaType.anime)
  tags, rank, rating   → metadata map
  airWeekday           → metadata map (可选)

CollectedBangumi     → CollectedMedia
  bangumiItem          → mediaItem (MediaItem)
  time                 → time
  type                 → type (收藏类型, 通用化)

History              → History (字段适配)
  bangumiItem          → mediaItem (MediaItem)
  adapterName          → sourceId
  bangumiId(int)       → mediaId (string)
  其余字段保持

DownloadRecord       → DownloadRecord (字段适配)
  bangumiId(int)       → mediaId (string)
  bangumiName          → title
  bangumiCover         → cover

VideoPlaybackArgs    → MediaPlaybackArgs
  bangumiItem          → mediaItem (MediaItem)
  plugin               → source (MediaSource)
  roads                → episodeGroups (List<MediaEpisodeGroup>)

Road                 → MediaEpisodeGroup + MediaEpisode[]
  name                 → group title
  data[urls]           → episodes[].url
  identifier[names]    → episodes[].title

SearchItem           → MediaItem (部分映射)
  name                 → title
  src                  → detailUrl
```

---

## 8. 新的 Rule Schema

### 8.1 新 Schema (v9) 设计

```yaml
# 版本
version: 9

# 规则基本信息
id: example_source
name: Example Source
base_url: https://example.com
type: video          # 可选: movie/tv/anime/variety/documentary/sports/video/other

# HTTP 头
headers:
  user_agent: "Mozilla/5.0 ..."
  referer: "https://example.com/"

# 搜索
search:
  mode: xpath        # xpath | api
  method: GET        # GET | POST
  url: /search?q={keyword}&page={page}

  # XPath 模式
  item:
    xpath: "//div[@class='item']"
    title:
      xpath: ".//h3/text()"
    cover:
      xpath: ".//img/@src"
    detail_url:
      xpath: ".//a/@href"
    description:
      xpath: ".//p/text()"
    year:
      xpath: ".//span[@class='year']/text()"

  # API 模式 (可选)
  # api:
  #   request:
  #     method: GET
  #     url: /api/search
  #     query:
  #       keyword: "{keyword}"
  #       page: "{page}"
  #   list_path: $.data[*]
  #   title_path: $.name
  #   cover_path: $.cover
  #   detail_url_path: $.url

  # 分页 (可选)
  pagination:
    page_start: 1
    page_size: 20

# 详情 (可选, 如果搜索结果已含全部信息则不需要)
detail:
  url: "{detail_url}"
  cover:
    xpath: "//img[@class='cover']/@src"
  description:
    xpath: "//div[@class='desc']/text()"
  year:
    xpath: "//span[@class='year']/text()"
  genre:
    xpath: "//span[@class='genre']/text()"

# 剧集
episodes:
  mode: xpath        # xpath | api
  url: "{detail_url}"

  # 分组 (可选, 如果没有分组则所有剧集在一个默认组中)
  group:
    xpath: "//div[@class='road']"
    title:
      xpath: ".//h4/text()"

  # 剧集项
  item:
    xpath: ".//a"
    title:
      xpath: "./text()"
    url:
      xpath: "./@href"

# 流解析 (可选, 如果播放页直接含 m3u8/mp4 URL)
stream:
  mode: xpath        # xpath | webview
  url: "{episode_url}"

  # XPath 模式: 直接从播放页提取流 URL
  url_xpath: "//source/@src"

  # WebView 模式: 使用 WebView JS 注入 (默认)
  # webview:
  #   use_legacy_parser: false

# 反爬 (可选)
anti_crawler:
  enabled: false
  captcha_type: 1    # 1=image, 2=button, 3=js
  captcha_image: ""
  captcha_input: ""
  captcha_button: ""
  captcha_detect_type: 1
  captcha_detect_value: ""
  captcha_script: ""

# 播放器配置
player:
  user_agent: ""
  referer: ""
  ad_blocker: false
  use_legacy_parser: false
```

### 8.2 与旧 Schema (v8) 的对比

| 旧 Schema (v8) | 新 Schema (v9) | 变化 |
|---|---|---|
| `api: "8"` | `version: 9` | 版本字段重命名 |
| `type: "anime"` | `type: "video"` (可选) | 默认类型改变 |
| `searchURL` (单字段) | `search.url` + `search.item.*` (结构化) | 搜索结果可提取更多字段 |
| `searchList/Name/Result` | `search.item.xpath/title/detail_url` | 结构化命名 |
| 无分页 | `search.pagination` | 新增 |
| 无详情解析 | `detail.*` | 新增 |
| `chapterRoads/Result` | `episodes.group/item` | 结构化, 支持分组标题 |
| 无流解析 | `stream.*` (xpath 或 webview) | 新增 |
| `usePost` | `search.method: POST` | 语义化 |
| `userAgent/referer` | `headers.*` + `player.*` | 区分请求头和播放器头 |
| `searchMode/chapterMode` | `search.mode/episodes.mode` | 结构化 |
| `searchApiConfig` | `search.api.*` | 结构化 |
| `chapterApiConfig` | `episodes.api.*` | 结构化 |
| `antiCrawlerConfig` | `anti_crawler.*` | 扁平化 |

### 8.3 变量支持

| 变量 | 上下文 | 说明 |
|---|---|---|
| `{keyword}` | search.url | 搜索关键词 |
| `{page}` | search.url | 分页页码 |
| `{detail_url}` | detail.url, episodes.url | 搜索结果详情页 URL |
| `{episode_url}` | stream.url | 剧集播放页 URL |
| `{source}` | episodes.url (API 模式) | 搜索结果 src |
| `{episodeUrl}` | stream.url (API 模式) | API 提取的剧集 URL |
| `{roadIndex}` / `{roadNumber}` | API 模式 | 线路索引 |
| `{episodeIndex}` / `{episodeNumber}` | API 模式 | 剧集索引 |

> **兼容**: 旧规则中的 `@keyword` 变量语法也继续支持。

### 8.4 LegacyRuleAdapter

```dart
/// 将旧版 Kazumi 规则 (v8) 适配为新版通用规则 (v9)
class LegacyRuleAdapter {
  /// 将旧 Plugin 转换为新 MediaRule
  static MediaRule fromPlugin(Plugin plugin) {
    return MediaRule(
      version: '9',
      id: plugin.name,
      name: plugin.name,
      baseUrl: plugin.baseUrl,
      type: plugin.type.isNotEmpty ? plugin.type : 'video',
      search: _adaptSearch(plugin),
      episodes: _adaptEpisodes(plugin),
      stream: _adaptStream(plugin),
      headers: RuleHeaders(
        userAgent: plugin.userAgent,
        referer: plugin.referer,
      ),
      antiCrawler: _adaptAntiCrawler(plugin.antiCrawlerConfig),
      // 保留旧字段供回退
      usePost: plugin.usePost,
      useLegacyParser: plugin.useLegacyParser,
      adBlocker: plugin.adBlocker,
      searchURL: plugin.searchURL,
      searchList: plugin.searchList,
      searchName: plugin.searchName,
      searchResult: plugin.searchResult,
      chapterRoads: plugin.chapterRoads,
      chapterResult: plugin.chapterResult,
      searchMode: plugin.searchMode,
      chapterMode: plugin.chapterMode,
      searchApiConfig: plugin.searchApiConfig,
      chapterApiConfig: plugin.chapterApiConfig,
    );
  }

  /// 将新 MediaRule 转换回旧 Plugin (用于序列化兼容)
  static Plugin toPlugin(MediaRule rule) { ... }
}
```

---

## 9. UI 重构方案

### 9.1 新导航结构

```
                    Universal Media App
                           │
             ┌─────────────┴─────────────┐
             │                           │
        Home (首页)              Settings (设置)
             │
    ┌────────┼────────┐
    │        │        │
  Search  Library  History
    │
    ▼
  Detail Page
    │
    ▼
  Video Player
```

### 9.2 新 Tab 结构

| Tab | 标签 | 图标 | 内容 |
|---|---|---|---|
| Home | 首页 | home | 搜索栏 + 最近观看 + 收藏入口 + 规则入口 |
| Library | 媒体库 | library | 收藏列表 (按类型筛选) + 下载列表 |
| History | 历史 | history | 观看历史 (按时间排序) |
| Settings | 设置 | settings | 所有设置 |

> 搜索不再是单独 Tab, 而是首页的核心入口。搜索结果以全屏页面呈现。

### 9.3 首页设计

```
┌─────────────────────────────────────┐
│  [🔍 搜索任意内容...]                 │  ← 搜索栏 (点击进入搜索页)
├─────────────────────────────────────┤
│  继续观看                             │
│  ┌──────┐ ┌──────┐ ┌──────┐         │  ← 最近观看 (水平滚动)
│  │Cover │ │Cover │ │Cover │         │
│  │EP 5  │ │EP 12 │ │EP 3  │         │
│  └──────┘ └──────┘ └──────┘         │
├─────────────────────────────────────┤
│  我的收藏                             │
│  ┌──────┐ ┌──────┐ ┌──────┐         │  ← 收藏 (水平滚动)
│  │Cover │ │Cover │ │Cover │         │
│  └──────┘ └──────┘ └──────┘         │
├─────────────────────────────────────┤
│  内容来源                             │
│  ┌─────────────────────────────────┐ │
│  │ Source A          [启用] [设置]  │ │  ← 规则列表
│  │ Source B          [启用] [设置]  │ │
│  │ + 添加规则                       │ │
│  └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

### 9.4 搜索结果页设计

```
┌─────────────────────────────────────┐
│  ← 庆余年                             │  ← 搜索栏 (带返回)
├─────────────────────────────────────┤
│  搜索历史: │庆余年│ │Breaking Bad│   │  ← 历史关键词
├─────────────────────────────────────┤
│  结果 (去重后)                        │
│                                       │
│  ┌─────────────────────────────────┐ │
│  │ [Cover] 庆余年                    │ │  ← 聚合结果 (多来源)
│  │         2019 · 电视剧             │ │
│  │         来源: Source A, B, C      │ │
│  └─────────────────────────────────┘ │
│                                       │
│  ┌─────────────────────────────────┐ │
│  │ [Cover] 庆余年第二季              │ │
│  │         2024 · 电视剧             │ │
│  │         来源: Source A            │ │
│  └─────────────────────────────────┘ │
│                                       │
│  其他结果 (未去重)                     │
│  ┌─────────────────────────────────┐ │
│  │ [Cover] 庆余年 (Source B)        │ │  ← 未聚合的独立结果
│  └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

### 9.5 详情页设计

```
┌─────────────────────────────────────┐
│  ← 庆余年                             │
├─────────────────────────────────────┤
│  [大封面]  庆余年                      │
│           2019 · 电视剧               │
│           ★ 8.5                       │
│                                       │
│  简介: 范闲带着神秘身世...             │
├─────────────────────────────────────┤
│  剧集                                 │
│  ┌─────────────────────────────────┐ │
│  │ ▼ 线路 1 (Source A)              │ │  ← 可折叠分组
│  │   1  2  3  4  5  6  7  8  ...   │ │
│  │ ▼ 线路 2 (Source B)              │ │
│  │   1  2  3  4  5  6  7  8  ...   │ │
│  └─────────────────────────────────┘ │
├─────────────────────────────────────┤
│  [♥ 收藏]  [⬇ 下载]  [💬 弹幕]        │
└─────────────────────────────────────┘
```

### 9.6 页面变更对照

| 旧页面 | 新页面 | 变化 |
|---|---|---|
| PopularPage (推荐) | HomePage (首页) | Bangumi 热门 → 搜索 + 最近观看 + 收藏 + 规则 |
| TimelinePage (时间表) | — | 删除 |
| CollectPage (追番) | LibraryPage (媒体库) | BangumiItem → MediaItem, 标题改变 |
| MyPage (我的) | — | 合并到 Settings, 统计移到首页 |
| SearchPage (Bangumi 搜索) | SearchPage (规则搜索) | Bangumi API → Rule Engine 并发 |
| ImageSearchPage | — | 删除 |
| InfoPage (番剧详情) | DetailPage (媒体详情) | 5 Tab (Bangumi) → 概览 + 剧集 + 来源 |
| SourceSheet | SourceSheet (保留) | 关键词从 nameCn → title |
| VideoPage | VideoPage (保留) | bangumiItem → mediaItem |
| HistoryPage | HistoryPage (保留) | BangumiItem → MediaItem |
| SettingsPage | SettingsPage (保留) | 移除 Bangumi 同步, 增加规则管理 |
| PluginEditorPage | RuleEditorPage (重命名) | 扩展支持新 Schema |
| PluginTestPage | RuleTesterPage (重命名) | 扩展支持新 Schema |
| PluginShopPage | RuleShopPage (重命名) | 保持 |
| OnboardingPage | OnboardingPage (保留) | 移除 Bangumi 镜像步骤 |

---

## 10. 分阶段迁移方案

### Phase 1: 架构分析 (当前阶段)

- [x] 完整分析 Kazumi 仓库
- [x] 输出 REFACTOR_PLAN.md
- [ ] 向用户汇报, 等待批准

**不修改任何业务代码。**

### Phase 2: 建立新数据模型 + Adapter

**目标**: 建立 `MediaItem`, `MediaDetail`, `MediaEpisode`, `MediaStream`, `MediaSource`, `MediaRule` 等新模型, 以及 `LegacyRuleAdapter`, `BangumiItemAdapter`。旧功能仍然能够运行。

**关键原则**: 新模型与旧模型共存, 通过 Adapter 互转。不修改旧代码的使用方。

### Phase 3: 抽离 Rule Engine

**目标**: 将 Rule Engine 从 `Plugin` 模型中抽离, 使其接受 `MediaRule` 而非 `Plugin`。通过 `LegacyRuleAdapter` 支持旧规则。

### Phase 4: 抽离 Search / Detail / Episode / Stream

**目标**: 让搜索、详情、剧集、流解析完全与 Anime 解耦。新增 `MediaSearchService`, `MediaDetailService`, `MediaEpisodeService`, `MediaStreamResolver`。旧 `PluginSearchService` 保持可用。

### Phase 5: 重构 UI

**目标**: 从 Anime App 变成 Universal Media App。新导航: Home / Library / History / Settings。搜索从 Bangumi API 变成规则搜索。

### Phase 6: Source Manager + Rule Editor + Rule Tester

**目标**: 完善规则管理: 添加/删除/启用/禁用/编辑/导入/导出/测试。增加 enable/disable + priority。

### Phase 7: History / Favorites / Continue Watching

**目标**: 完善 History (以 MediaItem 为键), Favorites (通用收藏), Continue Watching (首页最近观看)。

### Phase 8: 测试 + 平台验证

**目标**: Android/iOS 全面测试。MP4/M3U8/HLS/DASH/Headers/Referer/Cookie/Subtitle。

---

## 11. 每个阶段修改哪些文件

### Phase 2: 新数据模型 + Adapter

**新增文件**:
```
lib/modules/media/media_item.dart              — MediaItem 模型
lib/modules/media/media_detail.dart            — MediaDetail + MediaEpisodeGroup + MediaEpisode
lib/modules/media/media_stream.dart            — MediaStream 模型
lib/modules/media/media_source.dart            — MediaSource 模型
lib/modules/media/media_type.dart              — MediaType 枚举
lib/modules/media/media_rule.dart              — MediaRule 模型
lib/modules/media/collected_media.dart          — CollectedMedia (新收藏模型)
lib/modules/media/collected_media_change.dart   — CollectedMediaChange (变更日志)
lib/services/media/legacy_rule_adapter.dart    — LegacyRuleAdapter (Plugin ↔ MediaRule)
lib/services/media/bangumi_item_adapter.dart   — BangumiItemAdapter (BangumiItem ↔ MediaItem)
```

**修改文件** (仅增加, 不破坏):
```
lib/hive_registrar.g.dart                     — 注册新 Hive 适配器 (如果需要)
lib/services/storage/storage.dart              — 可选: 新增 media 相关 Box
```

**不修改的文件**: 所有现有代码保持不变, 旧功能继续运行。

### Phase 3: 抽离 Rule Engine

**新增文件**:
```
lib/services/media/media_rule_engine.dart      — 新 RuleEngine (接受 MediaRule)
lib/services/media/media_rule_strategy.dart    — 策略接口 (XPath / API)
lib/services/media/media_xpath_strategy.dart  — XPath 策略 (从 xpath_rule_strategy.dart 提取)
lib/services/media/media_api_strategy.dart     — API 策略 (从 api_rule_strategy.dart 提取)
lib/services/media/media_rule_models.dart      — 新模型 (PreparedRequest, SearchTrace, etc.)
lib/services/media/media_stream_resolver.dart  — 流解析器 (XPath + WebView)
```

**修改文件**:
```
lib/services/plugin/rule_engine.dart           — 内部委托给新引擎 (适配层)
lib/plugins/plugins.dart                       — Plugin 增加 toMediaRule() 方法
```

**不修改**: 旧 `PluginSearchService` 保持可用。

### Phase 4: 抽离 Search / Detail / Episode / Stream

**新增文件**:
```
lib/services/media/media_search_service.dart    — 多规则并发搜索 + 去重
lib/services/media/media_deduplicator.dart      — 结果去重
lib/services/media/media_detail_service.dart    — 详情解析
lib/services/media/media_episode_service.dart   — 剧集解析
```

**修改文件**:
```
lib/pages/info/source_sheet.dart               — 关键词从 nameCn → title (兼容)
lib/pages/search/search_controller.dart         — 增加规则搜索路径 (保留 Bangumi 搜索)
lib/pages/video/video_playback_args.dart        — 增加 MediaPlaybackArgs (保留旧 args)
```

### Phase 5: 重构 UI

**新增文件**:
```
lib/pages/home/home_page.dart                  — 新首页
lib/pages/home/home_controller.dart            — 首页控制器
lib/pages/home/home_module.dart                — 首页模块
lib/pages/library/library_page.dart            — 新媒体库 (替代 CollectPage)
lib/pages/library/library_controller.dart     — 媒体库控制器
lib/pages/library/library_module.dart          — 媒体库模块
lib/pages/media_detail/detail_page.dart        — 新详情页
lib/pages/media_detail/detail_controller.dart  — 详情控制器
lib/pages/media_detail/detail_module.dart      — 详情模块
lib/pages/search/media_search_page.dart        — 新搜索页 (规则搜索)
lib/pages/search/media_search_controller.dart  — 搜索控制器
lib/pages/search/media_search_module.dart      — 搜索模块
lib/bean/card/media_card.dart                  — 通用媒体卡片
```

**修改文件**:
```
lib/pages/router.dart                           — Tab 定义改为 home/library/history/settings
lib/pages/menu/menu.dart                        — 导航项改变
lib/pages/index_module.dart                     — 路由模块调整
lib/pages/index_page.dart                       — 保持 (壳)
lib/pages/onboarding/onboarding_page.dart       — 移除 Bangumi 镜像步骤
```

**标记 deprecated** (不删除):
```
lib/pages/popular/*                             — deprecated
lib/pages/timeline/*                             — deprecated
lib/pages/collect/collect_page.dart              — deprecated (由 library_page 替代)
lib/pages/info/info_page.dart                    — deprecated (由 detail_page 替代)
```

### Phase 6: Source Manager + Rule Editor

**修改文件**:
```
lib/plugins/plugins_controller.dart             — 增加 enable/disable, priority
lib/plugins/plugins.dart                        — 增加 enabled, priority 字段
lib/pages/plugin_editor/plugin_editor_page.dart — 扩展支持新 Schema 字段
lib/pages/plugin_editor/plugin_test_page.dart   — 扩展支持新 Schema 测试
lib/pages/plugin_editor/plugin_view_page.dart   — 增加 enable/disable 开关
lib/pages/plugin_editor/rule_management_widgets.dart — UI 调整
```

**新增文件**:
```
lib/pages/source_manager/source_manager_page.dart — Source 管理页
lib/pages/source_manager/source_card.dart         — Source 卡片
```

### Phase 7: History / Favorites / Continue Watching

**修改文件**:
```
lib/modules/history/history_module.dart          — bangumiItem → mediaItem (保持 Hive 兼容)
lib/repositories/history_repository.dart         — 键从 bangumiId → mediaId (string)
lib/modules/collect/collect_module.dart          → 替换为 collected_media.dart
lib/repositories/collect_crud_repository.dart    — 适配新模型
lib/pages/home/home_controller.dart              — 增加继续观看数据
lib/pages/history/history_list_view.dart         — 展示 MediaItem
lib/pages/history/history_record_tile.dart      — 展示 MediaItem
lib/pages/library/library_page.dart              — 展示 CollectedMedia
lib/pages/library/library_card.dart              — MediaItem 卡片
```

### Phase 8: 测试 + 平台验证

**新增测试**:
```
test/media_item_test.dart                       — MediaItem 模型测试
test/media_rule_test.dart                       — MediaRule 解析测试
test/legacy_rule_adapter_test.dart              — 旧规则适配测试
test/media_deduplicator_test.dart               — 去重测试
test/media_stream_resolver_test.dart            — 流解析测试
test/media_search_service_test.dart             — 搜索服务测试
test/media_detail_service_test.dart             — 详情服务测试
test/media_episode_service_test.dart            — 剧集服务测试
test/media_history_test.dart                    — 历史记录测试
test/media_favorites_test.dart                  — 收藏测试
test/media_search_integration_test.dart         — 搜索集成测试
test/media_playback_integration_test.dart       — 播放集成测试
```

**修改测试** (适配新模型):
```
test/rule_engine_test.dart                      — 适配新引擎
test/episode_url_test.dart                       — 保持 (通用)
test/episode_ref_test.dart                       — 适配
test/history_repository_test.dart               — 适配新模型
test/history_sync_test.dart                     — 适配
test/collect_sync_test.dart                     — 适配
test/plugin_import_parser_test.dart             — 保持
test/plugin_api_config_test.dart                — 保持
test/api_rule_engine_test.dart                  — 适配
```

---

## 12. 风险点

### 12.1 高风险

| 风险 | 影响 | 缓解策略 |
|---|---|---|
| **旧规则失效** | 现有用户安装的规则全部不可用 | `LegacyRuleAdapter` 保证旧规则 (v8) 在新引擎中正常工作; 不改变规则存储格式 |
| **Hive 数据迁移** | History/Collect/Download 中嵌入的 BangumiItem 与新 MediaItem 不兼容 | 新模型保留旧 Hive typeId; 使用 Adapter 在读取时转换; 写入时用新格式但保持旧字段 |
| **搜索体验降级** | 从 Bangumi 结构化搜索变为纯规则搜索, 可能结果质量下降 | Phase 4 保留 Bangumi 搜索作为可选; 规则搜索去重提升体验; 逐步迁移 |
| **弹幕功能丢失** | DanDanPlay 弹幕依赖 Bangumi ID, 通用化后无法使用 | 弹幕改为可选插件; 保留 DanDanPlay 作为可选弹幕源; 新增规则可声明弹幕来源 |
| **WebView 兼容性** | 各平台 WebView 实现差异大, 重构可能破坏 | WebView 模块完全复用, 不修改; 仅在流解析层增加 XPath 模式作为可选 |
| **播放器稳定性** | media_kit 配置复杂, 修改可能引入问题 | 播放器核心完全复用; 仅 PlaybackInitParams 字段适配 |

### 12.2 中风险

| 风险 | 影响 | 缓解策略 |
|---|---|---|
| **WebDAV 同步破坏** | 历史/收藏同步格式变化 | 同步 JSON 格式保持兼容; 新模型序列化包含旧字段 |
| **Bangumi 同步移除** | 依赖 Bangumi 同步的用户不满 | Bangumi 同步改为可选模块, 不删除代码 |
| **性能** | 多规则并发搜索可能比单 Bangumi API 搜索慢 | 限制并发数; 超时控制; 渐进式结果展示 |
| **规则复杂度** | 新 Schema 字段更多, 用户编写难度增加 | 保留旧字段兼容; 规则编辑器提供模板; 规则测试器实时反馈 |
| **iOS AVPlayer** | media_kit 在 iOS 上的特殊性 | 不修改播放器配置; 测试覆盖 iOS |

### 12.3 低风险

| 风险 | 影响 | 缓解策略 |
|---|---|---|
| **UI 破损** | 导航重构导致页面错乱 | 分阶段替换; 旧页面标记 deprecated 但保留 |
| **依赖冲突** | 新增依赖与现有冲突 | 不引入新依赖; 利用现有库 |
| **编译错误** | 大量修改导致编译失败 | 每个阶段完成后运行 `flutter analyze`; 保持旧代码可用 |

---

## 13. 兼容策略

### 13.1 旧规则兼容

```
旧 Kazumi 规则 (v8)
    │
    ▼
LegacyRuleAdapter.fromPlugin()
    │
    ▼
MediaRule (v9, 含 legacy 字段)
    │
    ▼
新 Rule Engine (优先使用新字段, 回退到 legacy 字段)
    │
    ▼
统一搜索/剧集/流解析结果
```

**具体措施**:
- `Plugin` 类保留, 不删除
- `PluginsController` 保留管理旧格式规则
- 新 `MediaRuleEngine` 接受 `MediaRule`, 通过 `LegacyRuleAdapter` 转换
- 旧 `RuleEngine` 保留, 作为适配层委托给新引擎
- 规则存储格式 (`plugins.json`) 不变
- 旧规则的 `@keyword` 变量继续支持
- `kazumi://` 导入格式继续支持

### 13.2 旧数据兼容

**History**:
```dart
// 旧 History (Hive typeId 1):
//   bangumiItem: BangumiItem (typeId 0)
//   adapterName: String
//   progresses: Map<int, Progress>
//
// 新 History (保持 typeId 1, 新增字段):
//   mediaItem: MediaItem (新字段, 序列化为 JSON)
//   sourceId: String (替代 adapterName)
//   progresses: Map<int, Progress> (不变)
//   bangumiItem: BangumiItem? (保留旧字段, 仅供迁移读取)
//   adapterName: String? (保留旧字段, 仅供迁移读取)
//
// 读取时: 优先 mediaItem, 回退 bangumiItem (通过 Adapter 转换)
// 写入时: 写入 mediaItem, 同时写入旧字段 (双写)
```

**Collect**:
```dart
// 旧 CollectedBangumi (Hive typeId 3):
//   bangumiItem: BangumiItem
//   time: DateTime
//   type: int
//
// 新 CollectedMedia (新 typeId 9, 旧 box 保持):
//   mediaItem: MediaItem (JSON 序列化)
//   time: DateTime
//   type: int
//
// 迁移: 启动时检测旧 collectibles box, 转换为 CollectedMedia, 写入新 box
// 旧 box 标记为 deprecated, 保留以防回退
```

**Download**:
```dart
// 旧 DownloadRecord (Hive typeId 7):
//   bangumiId: int, bangumiName: String, bangumiCover: String
//
// 新 DownloadRecord (保持 typeId 7, 新增字段):
//   mediaId: String, mediaTitle: String, mediaCover: String
//   bangumiId: int? (保留旧字段)
//   bangumiName: String? (保留旧字段)
//   bangumiCover: String? (保留旧字段)
//
// 读取时: 优先 mediaId, 回退 bangumiId
```

### 13.3 Bangumi 功能兼容

Bangumi 相关功能不删除, 改为可选模块:

```
Bangumi 模块 (可选)
  ├─ BangumiApi (元数据查询)
  ├─ BangumiClient (OAuth)
  ├─ Bangumi 同步 (收藏同步)
  ├─ Bangumi 日历 (可选 Tab)
  └─ Bangumi 搜索 (可选搜索源)
```

用户可以在设置中启用/禁用 Bangumi 模块。启用后:
- 搜索时, Bangumi 作为额外的"规则"参与搜索
- 详情页可以显示 Bangumi 元数据 (评分、标签、简介)
- 收藏可以同步到 Bangumi
- 弹幕可以通过 Bangumi ID 映射到 DanDanPlay

禁用后:
- 纯规则搜索
- 纯规则详情
- 本地收藏
- 无弹幕 (或规则提供弹幕源)

### 13.4 平台兼容

| 平台 | 风险 | 策略 |
|---|---|---|
| **Android** | media_kit 硬解, WebView, PiP | 不修改播放器和 WebView; 仅适配数据模型 |
| **iOS** | AVPlayer, flutter_inappwebview | 不修改播放器和 WebView; 测试覆盖 |
| **桌面** | window_manager, 系统代理 | 不修改窗口和代理; 仅适配导航 |

### 13.5 编译保证

每个阶段完成后:
1. `flutter analyze` 无错误
2. `flutter test` 全部通过
3. `flutter build apk --debug` 成功 (Android)
4. `flutter build ios --debug --no-codesign` 成功 (iOS, 如环境支持)
5. 手动验证: 搜索 → 详情 → 播放 全流程可用

---

## 附录 A: 关键文件索引

### 规则引擎
| 文件 | 行数 | 关键类/函数 |
|---|---|---|
| `lib/plugins/plugins.dart` | 269 | `Plugin` (规则模型) |
| `lib/plugins/api_rule_config.dart` | 237 | `ApiSearchConfig`, `ApiChapterConfig` |
| `lib/plugins/anti_crawler_config.dart` | 133 | `AntiCrawlerConfig` |
| `lib/plugins/plugins_controller.dart` | 571 | `PluginsController` (MobX store) |
| `lib/services/plugin/rule_engine.dart` | 355 | `RuleEngine.search()`, `queryChapters()` |
| `lib/services/plugin/rule_engine_models.dart` | 158 | `PreparedRuleRequest`, traces, exceptions |
| `lib/services/plugin/xpath_rule_strategy.dart` | 333 | `XPathRuleStrategy` |
| `lib/services/plugin/api_rule_strategy.dart` | 537 | `ApiRuleStrategy`, `RestrictedJsonPath` |
| `lib/services/plugin/plugin_search_service.dart` | 123 | `PluginSearchService.queryAllSource()` |
| `lib/services/plugin/plugin_import_parser.dart` | 176 | `PluginImportParser.parse()` |
| `lib/services/plugin/captcha_verification_service.dart` | 283 | `CaptchaVerificationService` |
| `lib/services/plugin/plugin_cookie_manager.dart` | 73 | `PluginCookieManager` |

### 视频源 & 播放器
| 文件 | 行数 | 关键类/函数 |
|---|---|---|
| `lib/services/video_source/webview_video_source_service.dart` | 160 | `WebViewVideoSourceService.resolve()` |
| `lib/services/video_source/video_source_service.dart` | 102 | `IVideoSourceService`, `VideoSource` |
| `lib/services/video_source/video_source_format.dart` | — | `VideoSourceFormat` enum |
| `lib/services/video_source/video_source_resolver_pool.dart` | — | 解析池 |
| `lib/pages/player/player_controller.dart` | 286 | `PlayerController.init()` |
| `lib/pages/player/controller/player_playback_controller.dart` | 482 | `createVideoController()`, `player.open()` |
| `lib/pages/player/controller/player_models.dart` | 43 | `PlaybackInitParams` |
| `lib/pages/player/player_item.dart` | 1521+ | 播放器 UI 主体 |
| `lib/pages/video/video_controller.dart` | 888 | `VideoPageController` |
| `lib/pages/video/video_playback_args.dart` | 43 | `VideoPlaybackArgs` |

### 领域模型
| 文件 | 行数 | 关键类 |
|---|---|---|
| `lib/modules/bangumi/bangumi_item.dart` | 140+ | `BangumiItem` |
| `lib/modules/collect/collect_module.dart` | 24 | `CollectedBangumi` |
| `lib/modules/collect/collect_change_module.dart` | — | `CollectedBangumiChange` |
| `lib/modules/history/history_module.dart` | 170+ | `History`, `Progress`, `PlaybackHistoryIdentity` |
| `lib/modules/download/download_module.dart` | 110+ | `DownloadRecord`, `DownloadEpisode` |
| `lib/modules/roads/road_module.dart` | 11 | `Road` |
| `lib/modules/search/plugin_search_module.dart` | 35 | `SearchItem`, `PluginSearchResponse` |
| `lib/modules/search/search_history_module.dart` | 15 | `SearchHistory` |
| `lib/modules/danmaku/danmaku_module.dart` | 49 | `DanmakuEntry` |

### 网络 & API
| 文件 | 行数 | 关键类/函数 |
|---|---|---|
| `lib/request/core/dio_factory.dart` | 125 | `DioFactory` (5 Dio 实例) |
| `lib/request/core/network_config.dart` | 114 | `NetworkConfig` |
| `lib/request/config/api_endpoints.dart` | 144 | 所有端点常量 |
| `lib/request/apis/bangumi_api.dart` | 770 | 全部 Bangumi 业务逻辑 |
| `lib/request/apis/danmaku_api.dart` | 75 | DanDanPlay 弹幕 API |
| `lib/request/apis/trace_api.dart` | 38 | trace.moe 图片搜索 |
| `lib/request/apis/plugin_catalog_api.dart` | 74 | 规则仓库目录 |
| `lib/request/clients/plugin_site_client.dart` | 45 | 规则目标网站 HTTP |

### 存储 & 仓储
| 文件 | 行数 | 关键类 |
|---|---|---|
| `lib/services/storage/storage.dart` | 381 | `GStorage` (8 Hive boxes) |
| `lib/services/storage/settings_keys.dart` | 674 | 80+ 设置键 |
| `lib/repositories/history_repository.dart` | 408 | `HistoryRepository` |
| `lib/repositories/collect_crud_repository.dart` | 201 | `CollectCrudRepository` |
| `lib/repositories/download_repository.dart` | 256 | `DownloadRepository` |
| `lib/repositories/search_history_repository.dart` | 151 | `SearchHistoryRepository` |

### UI 页面
| 文件 | 行数 | 关键类 |
|---|---|---|
| `lib/pages/index_module.dart` | 124 | 路由定义 |
| `lib/pages/router.dart` | 30 | Tab 定义 |
| `lib/pages/menu/menu.dart` | 221 | `ScaffoldMenu` (导航壳) |
| `lib/pages/info/info_controller.dart` | 295 | `InfoController` |
| `lib/pages/info/source_sheet.dart` | 219 | `SourceSheet` |
| `lib/pages/search/search_controller.dart` | — | `SearchPageController` |
| `lib/pages/video/video_page.dart` | — | `VideoPage` |

### 工具
| 文件 | 行数 | 关键函数 |
|---|---|---|
| `lib/utils/episode_url.dart` | 78 | `normalizeEpisodeUrl()` |
| `lib/utils/media.dart` | 36 | `decodeVideoSource()`, `extractEpisodeNumber()` |
| `lib/utils/m3u8_parser.dart` | 335 | `M3u8Parser` |
| `lib/utils/m3u8_ad_filter.dart` | 86 | `M3u8AdFilter.filterAds()` |
| `lib/utils/encoding.dart` | 60 | Base64 编解码 |
| `lib/utils/http_headers.dart` | 13 | `getRandomUA()` |

---

## 附录 B: 现有测试清单

| 测试文件 | 测试内容 |
|---|---|
| `test/rule_engine_test.dart` | 规则引擎 (XPath + API, 搜索 + 章节) |
| `test/api_rule_engine_test.dart` | API 规则引擎 |
| `test/plugin_api_config_test.dart` | 规则 API 配置 |
| `test/plugin_import_parser_test.dart` | 规则导入解析 |
| `test/episode_url_test.dart` | URL 规范化 |
| `test/episode_ref_test.dart` | 剧集引用 |
| `test/m3u8_parser_test.dart` | M3U8 解析 |
| `test/history_repository_test.dart` | 历史仓储 |
| `test/history_sync_test.dart` | 历史同步 |
| `test/collect_sync_test.dart` | 收藏同步 |
| `test/bangumi_search_params_test.dart` | Bangumi 搜索参数 |
| `test/bangumi_image_url_rewriter_test.dart` | Bangumi 图片 URL |
| `test/bangumi_sync_service_test.dart` | Bangumi 同步服务 |
| `test/bangumi_avatar_test.dart` | Bangumi 头像 |
| `test/search_parser_test.dart` | 搜索 DSL 解析 |
| `test/syncplay_endpoint_test.dart` | 同步播放端点 |
| `test/webdav_service_test.dart` | WebDAV 服务 |
| `test/dialog_helper_test.dart` | 对话框 |
| `test/dialog_task_test.dart` | 对话框任务 |
| `test/async_rate_limiter_test.dart` | 异步限流 |
| `test/async_session_test.dart` | 异步会话 |
| `test/async_single_flight_test.dart` | 单飞 |

---

*Document generated: 2026-10-08*
*Project: Kazumi → Universal XPath Media Shell*
*Phase: 1 (Analysis)*
