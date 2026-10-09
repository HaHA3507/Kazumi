/// 首页推荐配置（可选）
///
/// 配置后 App 首页会展示该来源网站的推荐内容：抓取 [url]（留空时使用
/// 规则的 baseURL），用 XPath 从页面中提取推荐条目。
///
/// 仅 XPath 模式。条目字段的 XPath 相对于 [homeList] 匹配的条目节点，
/// 语义与搜索规则（searchList/searchName/searchResult）一致。
class HomeConfig {
  /// 推荐页地址，留空使用规则 baseURL
  String url;

  /// 推荐条目列表 XPath
  String homeList;

  /// 推荐条目名称 XPath（相对条目）
  String homeName;

  /// 推荐条目详情链接 XPath（相对条目）
  String homeResult;

  /// 推荐条目封面 XPath（相对条目，可选）
  ///
  /// 留空时引擎会自动从条目节点内启发式提取图片。
  String homeCover;

  HomeConfig({
    this.url = '',
    this.homeList = '',
    this.homeName = '',
    this.homeResult = '',
    this.homeCover = '',
  });

  /// 列表、名称、链接齐全才算有效配置，缺失时推荐功能不生效。
  bool get isConfigured =>
      homeList.trim().isNotEmpty &&
      homeName.trim().isNotEmpty &&
      homeResult.trim().isNotEmpty;

  factory HomeConfig.fromJson(Map<String, dynamic> json) {
    return HomeConfig(
      url: json['url'] as String? ?? '',
      homeList: json['homeList'] as String? ?? '',
      homeName: json['homeName'] as String? ?? '',
      homeResult: json['homeResult'] as String? ?? '',
      homeCover: json['homeCover'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        if (url.isNotEmpty) 'url': url,
        'homeList': homeList,
        'homeName': homeName,
        'homeResult': homeResult,
        if (homeCover.isNotEmpty) 'homeCover': homeCover,
      };

  HomeConfig copyWith({
    String? url,
    String? homeList,
    String? homeName,
    String? homeResult,
    String? homeCover,
  }) {
    return HomeConfig(
      url: url ?? this.url,
      homeList: homeList ?? this.homeList,
      homeName: homeName ?? this.homeName,
      homeResult: homeResult ?? this.homeResult,
      homeCover: homeCover ?? this.homeCover,
    );
  }
}
