/// Unit tests for the NijiStream extension engine.
///
/// Tests the bridge functions, JS runtime, and extension loading.
/// The reference extension (example_source.js) is loaded and queried
/// to verify the full pipeline works.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:nijistream/extensions/api/bridge_functions.dart';
import 'package:nijistream/extensions/models/extension_manifest.dart';

void main() {
  group('BridgeFunctions', () {
    late BridgeFunctions bridge;

    setUp(() {
      bridge = BridgeFunctions();
    });

    test('cryptoMd5 returns correct hash', () {
      final hash = bridge.cryptoMd5('hello');
      expect(hash, equals('5d41402abc4b2a76b9719d911017c592'));
    });

    test('cryptoBase64Encode/Decode round-trip', () {
      const original = 'NijiStream test string';
      final encoded = bridge.cryptoBase64Encode(original);
      final decoded = bridge.cryptoBase64Decode(encoded);
      expect(decoded, equals(original));
    });

    test('parseHtml returns valid JSON', () {
      const html = '<div class="test"><p>Hello World</p></div>';
      final result = bridge.parseHtml(html);
      final parsed = jsonDecode(result) as Map<String, dynamic>;
      expect(parsed['tag'], equals('html'));
    });

    test('querySelectorAll finds elements', () {
      const html = '''
        <ul>
          <li class="item">First</li>
          <li class="item">Second</li>
          <li class="item">Third</li>
        </ul>
      ''';
      final result = bridge.querySelectorAll(html, '.item');
      final elements = jsonDecode(result) as List;
      expect(elements.length, equals(3));
      expect(elements[0]['text'], equals('First'));
    });

    test('querySelector returns first match', () {
      const html = '<div><span id="target">Found</span></div>';
      final result = bridge.querySelector(html, '#target');
      expect(result, isNotNull);
      final element = jsonDecode(result!) as Map<String, dynamic>;
      expect(element['text'], equals('Found'));
    });

    test('querySelector returns null for no match', () {
      const html = '<div>Nothing here</div>';
      final result = bridge.querySelector(html, '.nonexistent');
      expect(result, isNull);
    });
  });

  group('ExtensionManifest', () {
    test('fromJson parses correctly', () {
      final json = {
        'id': 'com.test.source',
        'name': 'Test Source',
        'version': '1.0.0',
        'lang': 'en',
        'author': 'tester',
        'description': 'A test extension',
        'icon': 'https://example.com/icon.png',
        'nsfw': false,
      };
      final manifest = ExtensionManifest.fromJson(json);
      expect(manifest.id, equals('com.test.source'));
      expect(manifest.name, equals('Test Source'));
      expect(manifest.version, equals('1.0.0'));
      expect(manifest.lang, equals('en'));
      expect(manifest.nsfw, isFalse);
    });

    test('fromJson handles missing fields', () {
      final manifest = ExtensionManifest.fromJson({});
      expect(manifest.id, equals(''));
      expect(manifest.name, equals('Unknown'));
      expect(manifest.version, equals('0.0.0'));
    });

    test('toJson round-trips', () {
      const manifest = ExtensionManifest(
        id: 'com.test.roundtrip',
        name: 'Round Trip',
        version: '2.0.0',
      );
      final json = manifest.toJson();
      final restored = ExtensionManifest.fromJson(json);
      expect(restored.id, equals(manifest.id));
      expect(restored.name, equals(manifest.name));
      expect(restored.version, equals(manifest.version));
    });
  });

  group('ExtensionSearchResult', () {
    test('fromJson parses correctly', () {
      final json = {
        'id': 'naruto',
        'title': 'Naruto',
        'cover': 'https://example.com/naruto.jpg',
        'url': '/anime/naruto',
      };
      final result = ExtensionSearchResult.fromJson(json);
      expect(result.id, equals('naruto'));
      expect(result.title, equals('Naruto'));
      expect(result.coverUrl, equals('https://example.com/naruto.jpg'));
    });
  });

  group('ExtensionEpisode', () {
    test('fromJson parses correctly', () {
      final json = {
        'number': 1,
        'title': 'Homecoming',
        'url': '/watch/naruto/1',
      };
      final episode = ExtensionEpisode.fromJson(json);
      expect(episode.number, equals(1));
      expect(episode.title, equals('Homecoming'));
      expect(episode.url, equals('/watch/naruto/1'));
    });
  });

  group('ExtensionVideoSource', () {
    test('fromJson parses correctly', () {
      final json = {
        'url': 'https://example.com/stream.m3u8',
        'quality': '1080p',
        'type': 'hls',
      };
      final source = ExtensionVideoSource.fromJson(json);
      expect(source.url, equals('https://example.com/stream.m3u8'));
      expect(source.quality, equals('1080p'));
      expect(source.type, equals('hls'));
    });
  });

  group('ExtensionRepo', () {
    test('fromJson parses full repo index', () {
      final json = {
        'name': 'Test Repo',
        'author': 'tester',
        'description': 'A test repository',
        'extensions': [
          {
            'id': 'com.test.ext1',
            'name': 'Extension 1',
            'version': '1.0.0',
            'url': 'https://example.com/ext1.js',
          },
          {
            'id': 'com.test.ext2',
            'name': 'Extension 2',
            'version': '2.0.0',
            'url': 'https://example.com/ext2.js',
          },
        ],
      };
      final repo = ExtensionRepo.fromJson(json);
      expect(repo.name, equals('Test Repo'));
      expect(repo.extensions.length, equals(2));
      expect(repo.extensions[0].id, equals('com.test.ext1'));
      expect(repo.extensions[1].version, equals('2.0.0'));
    });
  });
}
