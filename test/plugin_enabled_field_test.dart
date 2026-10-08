import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/plugins/plugins.dart';

void main() {
  group('Plugin.enabled field', () {
    test('fromJson defaults enabled to true when absent', () {
      final json = <String, dynamic>{
        'api': '8',
        'type': 'anime',
        'name': 'TestRule',
        'version': '1.0',
        'baseURL': 'https://example.com/',
        'searchURL': 'https://example.com/search',
        'searchList': '//div',
        'searchName': '//h3',
        'searchResult': '//a',
        'chapterRoads': '//ul',
        'chapterResult': '//li',
      };

      final plugin = Plugin.fromJson(json);

      expect(plugin.enabled, isTrue);
    });

    test('fromJson reads enabled=false when present', () {
      final json = <String, dynamic>{
        'api': '8',
        'type': 'anime',
        'name': 'DisabledRule',
        'version': '1.0',
        'baseURL': 'https://example.com/',
        'searchURL': 'https://example.com/search',
        'searchList': '//div',
        'searchName': '//h3',
        'searchResult': '//a',
        'chapterRoads': '//ul',
        'chapterResult': '//li',
        'enabled': false,
      };

      final plugin = Plugin.fromJson(json);

      expect(plugin.enabled, isFalse);
    });

    test('fromJson reads enabled=true when present', () {
      final json = <String, dynamic>{
        'api': '8',
        'type': 'anime',
        'name': 'EnabledRule',
        'version': '1.0',
        'baseURL': 'https://example.com/',
        'searchURL': 'https://example.com/search',
        'searchList': '//div',
        'searchName': '//h3',
        'searchResult': '//a',
        'chapterRoads': '//ul',
        'chapterResult': '//li',
        'enabled': true,
      };

      final plugin = Plugin.fromJson(json);

      expect(plugin.enabled, isTrue);
    });

    test('toJson omits enabled when true (backward compat)', () {
      final plugin = Plugin(
        api: '8',
        type: 'anime',
        name: 'Test',
        version: '1.0',
        muliSources: true,
        useWebview: true,
        useNativePlayer: true,
        usePost: false,
        useLegacyParser: false,
        adBlocker: false,
        userAgent: '',
        baseUrl: 'https://example.com/',
        searchURL: 'https://example.com/search',
        searchList: '//div',
        searchName: '//h3',
        searchResult: '//a',
        chapterRoads: '//ul',
        chapterResult: '//li',
        referer: '',
        enabled: true,
      );

      final json = plugin.toJson();

      expect(json.containsKey('enabled'), isFalse);
    });

    test('toJson includes enabled=false when disabled', () {
      final plugin = Plugin(
        api: '8',
        type: 'anime',
        name: 'Test',
        version: '1.0',
        muliSources: true,
        useWebview: true,
        useNativePlayer: true,
        usePost: false,
        useLegacyParser: false,
        adBlocker: false,
        userAgent: '',
        baseUrl: 'https://example.com/',
        searchURL: 'https://example.com/search',
        searchList: '//div',
        searchName: '//h3',
        searchResult: '//a',
        chapterRoads: '//ul',
        chapterResult: '//li',
        referer: '',
        enabled: false,
      );

      final json = plugin.toJson();

      expect(json['enabled'], isFalse);
    });

    test('fromTemplate creates enabled plugin', () {
      final plugin = Plugin.fromTemplate();

      expect(plugin.enabled, isTrue);
    });

    test('round-trip: disabled plugin survives toJson → fromJson', () {
      final original = Plugin(
        api: '8',
        type: 'anime',
        name: 'RoundTrip',
        version: '1.0',
        muliSources: true,
        useWebview: true,
        useNativePlayer: true,
        usePost: false,
        useLegacyParser: false,
        adBlocker: false,
        userAgent: '',
        baseUrl: 'https://example.com/',
        searchURL: '',
        searchList: '',
        searchName: '',
        searchResult: '',
        chapterRoads: '',
        chapterResult: '',
        referer: '',
        enabled: false,
      );

      final json = original.toJson();
      final restored = Plugin.fromJson(json);

      expect(restored.enabled, isFalse);
    });

    test('round-trip: enabled plugin survives toJson → fromJson', () {
      final original = Plugin(
        api: '8',
        type: 'anime',
        name: 'EnabledRoundTrip',
        version: '1.0',
        muliSources: true,
        useWebview: true,
        useNativePlayer: true,
        usePost: false,
        useLegacyParser: false,
        adBlocker: false,
        userAgent: '',
        baseUrl: 'https://example.com/',
        searchURL: '',
        searchList: '',
        searchName: '',
        searchResult: '',
        chapterRoads: '',
        chapterResult: '',
        referer: '',
        enabled: true,
      );

      final json = original.toJson();
      final restored = Plugin.fromJson(json);

      expect(restored.enabled, isTrue);
    });

    test('existing rule JSON without enabled field is backward compatible', () {
      // Simulate an old rule from plugins.json that predates the enabled field.
      final oldJson = '''
{
  "api": "4",
  "type": "anime",
  "name": "7sefun",
  "version": "1.3",
  "muliSources": true,
  "useWebview": true,
  "useNativePlayer": true,
  "userAgent": "",
  "baseURL": "https://www.7sefun.top/",
  "searchURL": "https://www.7sefun.top/vodsearch/-------------.html?wd=@keyword",
  "searchList": "//div[2]/div[2]/div[2]/div[2]/div",
  "searchName": "//div[2]/text()",
  "searchResult": "//a",
  "chapterRoads": "//div[2]/div[2]/div[2]/div/div[2]/div[1]//div",
  "chapterResult": "//a"
}
''';

      final json = Map<String, dynamic>.from(
        const JsonDecoder().convert(oldJson) as Map,
      );
      final plugin = Plugin.fromJson(json);

      expect(plugin.enabled, isTrue);
      expect(plugin.name, '7sefun');
    });
  });
}
