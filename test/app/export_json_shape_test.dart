/// 导出 JSON 的形状断言。
///
/// 覆盖 user story 41–43：
/// 整个结果导出成 JSON、语义字段与结构树都在、字段名用英文技术名。
///
/// 另外把「两次导出逐字节相同」「二进制值的确定��编码」钉死——
/// 下游脚本要靠它做 diff。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/app/export.dart';
import 'package:media_info/src/app/parse_service.dart';
import 'package:media_info/src/core/node.dart';
import 'package:media_info/src/core/tag.dart';

import '../support/document_builder.dart';
import '../support/fixture_paths.dart';

void main() {
  group('顶层键的集合与顺序', () {
    test('顶层键固定，且顺序固定', () {
      final Map<String, Object?> map = buildDocumentJsonMap(buildDocument());

      expect(map.keys.toList(), <String>[
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

    test('tool 与 schemaVersion 是固定值', () {
      final Map<String, Object?> map = buildDocumentJsonMap(buildDocument());

      expect(map['tool'], 'media_info');
      expect(map['schemaVersion'], 1);
      expect(kExportToolName, 'media_info');
      expect(kExportSchemaVersion, 1);
    });

    test('文件级的元信息被原样带出去', () {
      final Map<String, Object?> map = buildDocumentJsonMap(
        buildDocument(
          path: 'C:/media/a.mp4',
          detectedFormat: 'MP4',
          truncated: true,
          error: '文件在偏移 100 处截断',
          extensionWarning: '扩展名 `.wav` 与实际格式 `MP4` 不符',
        ),
      );

      expect(map['path'], 'C:/media/a.mp4');
      expect(map['format'], 'MP4');
      expect(map['truncated'], isTrue);
      expect(map['error'], '文件在偏移 100 处截断');
      expect(map['extensionWarning'], '扩展名 `.wav` 与实际格式 `MP4` 不符');
    });

    test('无法识别的文件：format 与 error 都是 null', () {
      final Map<String, Object?> map = buildDocumentJsonMap(
        buildDocument(detectedFormat: null),
      );

      expect(map['format'], isNull);
      expect(map['error'], isNull);
      expect(map['truncated'], isFalse);
    });
  });

  group('语义字段区', () {
    test('fileFields 用英文技术名做键', () {
      final Map<String, Object?> map = buildDocumentJsonMap(
        buildDocument(
          fileFields: <SemanticField>[
            buildField('sample_rate', label: '采样率', value: 44100, unit: 'Hz'),
          ],
        ),
      );

      final Map<String, Object?> fields =
          map['fileFields']! as Map<String, Object?>;
      expect(fields.keys.toList(), <String>['sample_rate']);
      expect(fields['sample_rate'], isA<Map<String, Object?>>());
    });

    test('字段对象的键与顺序固定：label / value / unit / origin / source', () {
      final Map<String, Object?> map = buildDocumentJsonMap(
        buildDocument(
          fileFields: <SemanticField>[
            buildField(
              'overall_bitrate',
              label: '平均码率',
              value: 93264,
              unit: 'bit/s',
              origin: FieldOrigin.derived,
              source: 'mvhd',
            ),
          ],
        ),
      );

      final Map<String, Object?> fields =
          map['fileFields']! as Map<String, Object?>;
      final Map<String, Object?> field =
          fields['overall_bitrate']! as Map<String, Object?>;
      expect(field.keys.toList(), <String>[
        'label',
        'value',
        'unit',
        'origin',
        'source',
      ]);
      expect(field['label'], '平均码率');
      expect(field['value'], 93264);
      expect(field['unit'], 'bit/s');
      expect(field['origin'], 'derived');
      expect(field['source'], 'mvhd');
    });

    test('来源为「文件里直接写的」时 origin 是 read', () {
      final Map<String, Object?> map = buildDocumentJsonMap(
        buildDocument(
          fileFields: <SemanticField>[buildField('duration', value: 1.0)],
        ),
      );

      final Map<String, Object?> fields =
          map['fileFields']! as Map<String, Object?>;
      final Map<String, Object?> field =
          fields['duration']! as Map<String, Object?>;
      expect(field['origin'], 'read');
    });

    test('重名的字段不会被丢掉：第二个起加 #2 后缀', () {
      final Map<String, Object?> map = buildDocumentJsonMap(
        buildDocument(
          fileFields: <SemanticField>[
            buildField('codec', value: 'avc1'),
            buildField('codec', value: 'mp4a'),
            buildField('codec', value: 'ac3'),
          ],
        ),
      );

      final Map<String, Object?> fields =
          map['fileFields']! as Map<String, Object?>;
      expect(fields.keys.toList(), <String>['codec', 'codec#2', 'codec#3']);
      expect((fields['codec#2']! as Map<String, Object?>)['value'], 'mp4a');
    });

    test('tracks 按轨道分组，每组带 trackIndex 与字段表', () {
      final Map<String, Object?> map = buildDocumentJsonMap(
        buildDocument(
          tracks: <TrackFields>[
            buildTrack(0, <SemanticField>[buildField('codec', value: 'avc1')]),
            buildTrack(1, <SemanticField>[buildField('codec', value: 'mp4a')]),
          ],
        ),
      );

      final List<Object?> tracks = map['tracks']! as List<Object?>;
      expect(tracks, hasLength(2));
      final Map<String, Object?> first = tracks[0]! as Map<String, Object?>;
      expect(first.keys.toList(), <String>['trackIndex', 'fields']);
      expect(first['trackIndex'], 0);
      final Map<String, Object?> fields =
          first['fields']! as Map<String, Object?>;
      expect(fields.keys.toList(), <String>['codec']);
    });

    test('没有轨道时 tracks 是空列表（不是 null）', () {
      final Map<String, Object?> map = buildDocumentJsonMap(buildDocument());

      expect(map['tracks'], isEmpty);
      expect(map['tags'], isEmpty);
    });
  });

  group('标签区', () {
    test('每个标签是 key / value / source 三个键', () {
      final Map<String, Object?> map = buildDocumentJsonMap(
        buildDocument(tags: <Tag>[buildTag('©nam', 'Song', source: 'ilst')]),
      );

      final List<Object?> tags = map['tags']! as List<Object?>;
      expect(tags, hasLength(1));
      final Map<String, Object?> tag = tags[0]! as Map<String, Object?>;
      expect(tag.keys.toList(), <String>['key', 'value', 'source']);
      expect(tag['key'], '©nam');
      expect(tag['value'], 'Song');
      expect(tag['source'], 'ilst');
    });

    test('重复的 key 都保留（不合并成 map）', () {
      final Map<String, Object?> map = buildDocumentJsonMap(
        buildDocument(
          tags: <Tag>[
            buildTag('covr', 'first', source: 'ilst'),
            buildTag('covr', 'second', source: 'ilst'),
          ],
        ),
      );

      final List<Object?> tags = map['tags']! as List<Object?>;
      expect(tags, hasLength(2));
      expect((tags[0]! as Map<String, Object?>)['value'], 'first');
      expect((tags[1]! as Map<String, Object?>)['value'], 'second');
    });

    test('二进制标签值确定性地编码成 base64', () {
      final Map<String, Object?> map = buildDocumentJsonMap(
        buildDocument(
          tags: <Tag>[
            buildTag(
              'covr',
              Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47]),
              source: 'ilst',
            ),
          ],
        ),
      );

      final List<Object?> tags = map['tags']! as List<Object?>;
      final Map<String, Object?> tag = tags[0]! as Map<String, Object?>;
      expect(tag['value'], <String, Object?>{
        'kind': 'binary',
        'base64': base64Encode(<int>[0x89, 0x50, 0x4E, 0x47]),
      });
    });
  });

  group('结构树区', () {
    test('结构树的节点键与顺序固定', () {
      final Map<String, Object?> map = buildDocumentJsonMap(
        buildDocument(
          root: buildNode(
            'MP4',
            0,
            100,
            children: <ContainerNode>[buildNode('mdat', 40, 60)],
          ),
        ),
      );

      final Map<String, Object?> structure =
          map['structure']! as Map<String, Object?>;
      expect(structure.keys.toList(), <String>[
        'type',
        'offset',
        'size',
        'dataOffset',
        'dataSize',
        'isOpaque',
        'fields',
        'children',
      ]);
      expect(structure['type'], 'MP4');
      expect(structure['offset'], 0);
      expect(structure['size'], 100);
      expect(structure['isOpaque'], isFalse);
      expect(structure['children'], hasLength(1));
    });

    test('结构树是递归的', () {
      final Map<String, Object?> map = buildDocumentJsonMap(
        buildDocument(
          root: buildNode(
            'MP4',
            0,
            100,
            children: <ContainerNode>[
              buildNode(
                'moov',
                8,
                92,
                children: <ContainerNode>[buildNode('trak', 16, 84)],
              ),
            ],
          ),
        ),
      );

      final Map<String, Object?> structure =
          map['structure']! as Map<String, Object?>;
      final List<Object?> children = structure['children']! as List<Object?>;
      final Map<String, Object?> moov = children[0]! as Map<String, Object?>;
      expect(moov['type'], 'moov');
      final List<Object?> grandChildren = moov['children']! as List<Object?>;
      expect((grandChildren[0]! as Map<String, Object?>)['type'], 'trak');
    });

    test('没有结构时 structure 是 null', () {
      final Map<String, Object?> map = buildDocumentJsonMap(
        buildDocument(root: null),
      );

      expect(map['structure'], isNull);
    });
  });

  group('两次导出逐字节相同', () {
    test('同一个文档导出两次，文本完全一致', () {
      final ParsedDocument doc = parseFile(
        fixturePath('mp4_h264_aac_320x240.normal.mp4'),
      );

      expect(buildDocumentJson(doc), buildDocumentJson(doc));
    });

    test('两次独立解析出来的文档导出结果也完全一致', () {
      final String first = buildDocumentJson(
        parseFile(fixturePath('mp4_h264_aac_320x240.normal.mp4')),
      );
      final String second = buildDocumentJson(
        parseFile(fixturePath('mp4_h264_aac_320x240.normal.mp4')),
      );

      expect(first, second);
    });

    test('导出的文本是带缩进的合法 JSON，末尾带换行', () {
      final String json = buildDocumentJson(buildDocument());

      expect(json.endsWith('\n'), isTrue);
      expect(json, contains('\n  "tool": "media_info"'));
      expect(jsonDecode(json), isA<Map<String, Object?>>());
    });

    test('写文件写出来的内容与 buildDocumentJson 一致', () async {
      final Directory dir = Directory.systemTemp.createTempSync(
        'media_info_export',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final String path = '${dir.path}/out.json';

      final ParsedDocument doc = parseFile(
        fixturePath('wav_pcm_s16le_44100_stereo.normal.wav'),
      );
      await writeDocumentJson(doc, path);

      expect(
        File(path).readAsStringSync(encoding: utf8),
        buildDocumentJson(doc),
      );
    });
  });

  group('导出用的文件名', () {
    test('默认文件名是源文件名加 .json', () {
      expect(
        suggestedJsonFileName(buildDocument(path: 'C:/media/a.mp4')),
        'a.mp4.json',
      );
    });

    test('Windows 的反斜杠路径也只取文件名', () {
      expect(
        suggestedJsonFileName(buildDocument(path: r'C:\media\a.mp4')),
        'a.mp4.json',
      );
    });

    test('已经是 .json 的名字不再加后缀', () {
      expect(suggestedJsonFileName(buildDocument(path: 'a.json')), 'a.json');
    });

    test('空路径退回到 media_info.json', () {
      expect(suggestedJsonFileName(buildDocument(path: '')), 'media_info.json');
    });
  });
}
