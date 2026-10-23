/// 导出 JSON 的形状测试（**纯函数**：`buildDocumentJsonMap` / `buildDocumentJson`）。
///
/// 这里用**真实解析出来的文档**做输入——导出的是用户手上的文件，不该是
/// 手写的样本。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/app/export.dart';
import 'package:media_info/src/app/parse_service.dart';
import 'package:media_info/src/core/tag.dart';

/// 真实素材：H.264 + AAC 的 MP4。
const String mp4Fixture = 'test/fixtures/mp4_h264_aac_320x240.normal.mp4';

/// 取一个 Map 类型的字段。
Map<String, Object?> _map(Object? value) => value! as Map<String, Object?>;

/// 取一个 List 类型的字段。
List<Object?> _list(Object? value) => value! as List<Object?>;

void main() {
  group('分区', () {
    test('顶层按「文件级 / 轨道级 / 标签」分区，外加结构树', () {
      final json = buildDocumentJsonMap(parseFile(mp4Fixture));

      expect(json['fileFields'], isA<Map<String, Object?>>());
      expect(json['tracks'], isA<List<Object?>>());
      expect(json['tags'], isA<List<Object?>>());
      expect(json['structure'], isA<Map<String, Object?>>());
    });

    test('顶层键名与顺序固定', () {
      final json = buildDocumentJsonMap(parseFile(mp4Fixture));

      expect(json.keys, <String>[
        'tool',
        'schemaVersion',
        'path',
        'format',
        'truncated',
        'error',
        'extensionWarning',
        'fileFields',
        'tracks',
        'tags',
        'structure',
      ]);
    });

    test('文件级字段用英文技术名做 key，另附中文显示名', () {
      final json = buildDocumentJsonMap(parseFile(mp4Fixture));
      final fileFields = _map(json['fileFields']);

      expect(
        fileFields.keys,
        containsAll(<String>['file_name', 'file_size', 'container_format']),
      );
      expect(_map(fileFields['file_name'])['label'], '文件名');
      expect(_map(fileFields['file_size'])['unit'], 'byte');
      expect(_map(fileFields['container_format'])['value'], 'isom');
    });

    test('轨道级字段按轨道分组，每组带轨道序号', () {
      final json = buildDocumentJsonMap(parseFile(mp4Fixture));
      final tracks = _list(json['tracks']);

      expect(tracks, hasLength(2));
      expect(_map(tracks.first)['trackIndex'], 0);
      expect(_map(tracks.last)['trackIndex'], 1);

      // codec 标识保持英文原样。
      final videoFields = _map(_map(tracks.first)['fields']);
      expect(_map(videoFields['codec'])['value'], 'avc1');
    });

    test('标签区段保留 key 与来源', () {
      final document = parseFile(mp4Fixture);
      final json = buildDocumentJsonMap(document);

      expect(json['tags'], isA<List<Object?>>());
      for (final entry in _list(json['tags'])) {
        final tag = _map(entry);
        expect(tag.keys, containsAll(<String>['key', 'value', 'source']));
      }
    });
  });

  group('结构树', () {
    test('结构树是递归的：子节点里还有子节点', () {
      final json = buildDocumentJsonMap(parseFile(mp4Fixture));
      final structure = _map(json['structure']);

      expect(structure['type'], 'MP4');
      expect(structure['offset'], 0);
      expect(structure['isOpaque'], isFalse);

      final children = _list(structure['children']);
      expect(children, isNotEmpty);

      // 第一层：`ftyp` / `moov` …
      final types = children.map((Object? child) => _map(child)['type']);
      expect(types, contains('ftyp'));
      expect(types, contains('moov'));

      // 第二层：`moov` 里有 `trak` —— 说明递归不是只做一层。
      final moov = children
          .map(_map)
          .firstWhere((Map<String, Object?> node) => node['type'] == 'moov');
      final moovChildren = _list(moov['children']);
      expect(
        moovChildren.map((Object? child) => _map(child)['type']),
        contains('trak'),
      );

      // 第三层：`trak` 里有 `mdia`。
      final trak = moovChildren
          .map(_map)
          .firstWhere((Map<String, Object?> node) => node['type'] == 'trak');
      expect(
        _list(trak['children']).map((Object? child) => _map(child)['type']),
        contains('mdia'),
      );
    });

    test('每个节点都带 type / offset / size / isOpaque / fields / children', () {
      final json = buildDocumentJsonMap(parseFile(mp4Fixture));
      final structure = _map(json['structure']);

      expect(
        structure.keys,
        containsAll(<String>[
          'type',
          'offset',
          'size',
          'isOpaque',
          'fields',
          'children',
        ]),
      );
    });
  });

  group('确定性', () {
    test('同一份文档导出两次，JSON 文本完全一致', () {
      final document = parseFile(mp4Fixture);

      expect(buildDocumentJson(document), buildDocumentJson(document));
    });

    test('键名顺序在 JSON 文本里也是稳定的', () {
      final document = parseFile(mp4Fixture);
      final text = buildDocumentJson(document);

      final keys = RegExp(
        r'^  "([a-zA-Z]+)":',
        multiLine: true,
      ).allMatches(text).map((Match m) => m.group(1)).toList();

      expect(keys, <String>[
        'tool',
        'schemaVersion',
        'path',
        'format',
        'truncated',
        'error',
        'extensionWarning',
        'fileFields',
        'tracks',
        'tags',
        'structure',
      ]);
    });

    test('二进制标签值确定性地编码成 base64，不吐裸字节', () {
      final document = ParsedDocument(
        path: 'C:/media/cover.mp4',
        detectedFormat: 'MP4',
        tags: <Tag>[
          Tag(
            key: 'covr',
            value: Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47]),
            source: 'ilst',
          ),
        ],
      );

      final first = _map(_list(buildDocumentJsonMap(document)['tags']).first);
      final second = _map(_list(buildDocumentJsonMap(document)['tags']).first);

      final value = _map(first['value']);
      expect(value['kind'], 'binary');
      expect(value['base64'], base64Encode(<int>[0x89, 0x50, 0x4E, 0x47]));
      expect(second['value'], first['value']);
    });

    test('导出的文本是合法的 JSON', () {
      final text = buildDocumentJson(parseFile(mp4Fixture));

      expect(() => jsonDecode(text), returnsNormally);
    });
  });
}
