/// 导出层的行为测试：JSON 的形状、值复制的格式化、写文件的接缝。
///
/// 这些测试只走公开接口（`lib/src/app/export.dart`），不碰内部实现。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/app/export.dart';
import 'package:media_info/src/app/parse_service.dart';
import 'package:media_info/src/core/node.dart';
import 'package:media_info/src/core/tag.dart';

/// 造一个覆盖各种字段形态的文档（手写，不依赖素材）。
ParsedDocument _sampleDocument() {
  return ParsedDocument(
    path: 'C:/media/sample.wav',
    detectedFormat: 'WAV',
    root: const ContainerNode(
      type: 'RIFF',
      offset: 0,
      size: 100,
      dataOffset: 12,
      dataSize: 88,
      children: <ContainerNode>[
        ContainerNode(
          type: 'fmt ',
          offset: 12,
          size: 16,
          dataOffset: 20,
          dataSize: 8,
          isOpaque: true,
          fields: <SemanticField>[
            SemanticField(
              key: 'sample_rate',
              label: '采样率',
              value: 44100,
              unit: 'Hz',
              source: 'fmt ',
            ),
          ],
        ),
      ],
    ),
    fileFields: const <SemanticField>[
      SemanticField(key: 'file_name', label: '文件名', value: 'sample.wav'),
      SemanticField(key: 'duration', label: '时长', value: 44100.0, unit: 's'),
      SemanticField(
        key: 'overall_bitrate',
        label: '平均码率',
        value: 1411200,
        unit: 'bit/s',
        origin: FieldOrigin.derived,
      ),
    ],
    tracks: const <TrackFields>[
      TrackFields(
        trackIndex: 0,
        fields: <SemanticField>[
          SemanticField(
            key: 'codec',
            label: '编码标识',
            value: 'PCM',
            scope: FieldScope.track,
            trackIndex: 0,
            source: 'fmt ',
          ),
        ],
      ),
    ],
    tags: <Tag>[
      const Tag(key: 'TITLE', value: 'Song', source: 'VORBIS_COMMENT'),
      Tag(
        key: 'covr',
        value: Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47]),
        source: 'ilst',
      ),
    ],
  );
}

void main() {
  group('导出 JSON 的结构', () {
    test('顶层含文件路径与检测到的格式', () {
      final json = buildDocumentJsonMap(_sampleDocument());

      expect(json['path'], 'C:/media/sample.wav');
      expect(json['format'], 'WAV');
    });

    test('语义字段按「文件级 / 轨道级 / 标签」分区', () {
      final json = buildDocumentJsonMap(_sampleDocument());

      expect(json['fileFields'], isA<Map<String, Object?>>());
      expect(json['tracks'], isA<List<Object?>>());
      expect(json['tags'], isA<List<Object?>>());
    });

    test('字段用英文技术名做 key，另附中文显示名', () {
      final json = buildDocumentJsonMap(_sampleDocument());
      final fileFields = json['fileFields']! as Map<String, Object?>;

      expect(fileFields.keys, contains('duration'));
      final duration = fileFields['duration']! as Map<String, Object?>;
      expect(duration['label'], '时长');
    });

    test('字段的 origin 与 unit 不丢失', () {
      final json = buildDocumentJsonMap(_sampleDocument());
      final fileFields = json['fileFields']! as Map<String, Object?>;

      final duration = fileFields['duration']! as Map<String, Object?>;
      expect(duration['origin'], 'read');
      expect(duration['unit'], 's');

      final bitrate = fileFields['overall_bitrate']! as Map<String, Object?>;
      expect(bitrate['origin'], 'derived');
      expect(bitrate['unit'], 'bit/s');
    });

    test('codec 标识保持英文原样，不翻译', () {
      final json = buildDocumentJsonMap(_sampleDocument());
      final tracks = json['tracks']! as List<Object?>;
      final track = tracks.first! as Map<String, Object?>;
      final fields = track['fields']! as Map<String, Object?>;

      expect(fields['codec'], isA<Map<String, Object?>>());
      expect((fields['codec']! as Map<String, Object?>)['value'], 'PCM');
    });

    test('轨道带轨道序号', () {
      final json = buildDocumentJsonMap(_sampleDocument());
      final tracks = json['tracks']! as List<Object?>;

      expect(tracks.length, 1);
      expect((tracks.first! as Map<String, Object?>)['trackIndex'], 0);
    });

    test('标签保留英文 key 与来源', () {
      final json = buildDocumentJsonMap(_sampleDocument());
      final tags = json['tags']! as List<Object?>;

      expect(tags.length, 2);
      final title = tags.first! as Map<String, Object?>;
      expect(title['key'], 'TITLE');
      expect(title['value'], 'Song');
      expect(title['source'], 'VORBIS_COMMENT');
    });

    test('二进制标签值确定性地编码成 base64，不吐裸字节', () {
      final json = buildDocumentJsonMap(_sampleDocument());
      final tags = json['tags']! as List<Object?>;
      final cover = tags.last! as Map<String, Object?>;

      expect(cover['value'], isA<Map<String, Object?>>());
      final encoded = cover['value']! as Map<String, Object?>;
      expect(encoded['kind'], 'binary');
      expect(encoded['base64'], base64Encode(<int>[0x89, 0x50, 0x4E, 0x47]));
    });

    test('结构树是递归的，每个节点含 type / offset / size / isOpaque / children', () {
      final json = buildDocumentJsonMap(_sampleDocument());
      final structure = json['structure']! as Map<String, Object?>;

      expect(structure['type'], 'RIFF');
      expect(structure['offset'], 0);
      expect(structure['size'], 100);
      expect(structure['isOpaque'], isFalse);

      final children = structure['children']! as List<Object?>;
      expect(children.length, 1);
      final child = children.first! as Map<String, Object?>;
      expect(child['type'], 'fmt ');
      expect(child['isOpaque'], isTrue);
      expect(child['fields'], isA<Map<String, Object?>>());
    });

    test('结构树里的字段也带 key 与 value', () {
      final json = buildDocumentJsonMap(_sampleDocument());
      final structure = json['structure']! as Map<String, Object?>;
      final children = structure['children']! as List<Object?>;
      final child = children.first! as Map<String, Object?>;
      final fields = child['fields']! as Map<String, Object?>;

      expect(fields.containsKey('sample_rate'), isTrue);
      expect((fields['sample_rate']! as Map<String, Object?>)['value'], 44100);
    });

    test('键名顺序稳定：两次导出完全一致', () {
      final document = _sampleDocument();

      expect(buildDocumentJson(document), buildDocumentJson(document));
    });

    test('JSON 用缩进输出，可读可 diff', () {
      final text = buildDocumentJson(_sampleDocument());

      expect(text, contains('\n  "path"'));
      expect(() => jsonDecode(text), returnsNormally);
    });
  });

  group('真实素材的导出', () {
    test('WAV 文件导出后仍能读回结构树', () {
      final document = parseFile(
        'test/fixtures/wav_pcm_s16le_44100_stereo.normal.wav',
      );
      final json = buildDocumentJsonMap(document);

      final structure = json['structure']! as Map<String, Object?>;
      expect(structure['type'], 'WAV');
      final fileFields = json['fileFields']! as Map<String, Object?>;
      expect(fileFields.containsKey('file_name'), isTrue);
      expect(fileFields.containsKey('file_size'), isTrue);
      expect(fileFields.containsKey('container_format'), isTrue);
    });

    test('每种素材的文件级字段都不重名（导出的 map 不会丢字段）', () {
      for (final fixture in const <String>[
        'wav_pcm_s16le_44100_stereo.normal.wav',
        'aiff_pcm_s16be_48000_mono.normal.aiff',
        'flac_s16_44100_stereo.normal.flac',
        'mp3_cbr128_44100_stereo.normal.mp3',
        'mp4_h264_aac_320x240.normal.mp4',
        'mkv_vp9_opus_320x240.normal.mkv',
        'webm_vp8_vorbis_320x240.normal.webm',
      ]) {
        final document = parseFile('test/fixtures/$fixture');
        final keys = document.fileFields.map((f) => f.key).toList();
        expect(
          keys.toSet().length,
          keys.length,
          reason: '$fixture 有重名的文件级字段：$keys',
        );
      }
    });
  });

  group('写文件的接缝', () {
    test('写到指定路径的内容与 JSON 文本一致', () async {
      final dir = Directory.systemTemp.createTempSync('media_info_export');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/out.json';

      await writeDocumentJson(_sampleDocument(), path);

      expect(
        File(path).readAsStringSync(),
        buildDocumentJson(_sampleDocument()),
      );
    });
  });

  group('导出流程：保存对话框 → 写文件', () {
    // file_selector 的方法通道——测试里假装平台弹了保存对话框。
    const MethodChannel channel = MethodChannel(
      'plugins.flutter.io/file_selector',
    );

    /// 让保存对话框返回 [path]（null = 用户取消）。
    void mockSaveDialog(String? path) {
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            if (call.method == 'getSavePath') return path;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
    }

    test('对话框给了路径就把 JSON 写进去', () async {
      final dir = Directory.systemTemp.createTempSync('media_info_export');
      addTearDown(() => dir.deleteSync(recursive: true));
      final target = '${dir.path}/out.json';
      mockSaveDialog(target);

      await exportDocumentToJson(_sampleDocument());

      expect(File(target).existsSync(), isTrue);
      expect(
        File(target).readAsStringSync(),
        buildDocumentJson(_sampleDocument()),
      );
    });

    test('用户取消对话框时不写文件', () async {
      final dir = Directory.systemTemp.createTempSync('media_info_export');
      addTearDown(() => dir.deleteSync(recursive: true));
      mockSaveDialog(null);

      await exportDocumentToJson(_sampleDocument());

      expect(dir.listSync(), isEmpty);
    });

    test('对话框给的文件名没有扩展名时补上 .json', () async {
      final dir = Directory.systemTemp.createTempSync('media_info_export');
      addTearDown(() => dir.deleteSync(recursive: true));
      mockSaveDialog('${dir.path}/out');

      await exportDocumentToJson(_sampleDocument());

      expect(File('${dir.path}/out.json').existsSync(), isTrue);
    });

    test('默认文件名是源文件名加 .json', () {
      expect(suggestedJsonFileName(_sampleDocument()), 'sample.wav.json');
    });
  });

  group('复制用的值格式化', () {
    test('数值直接用其字符串形式', () {
      expect(formatCopiedValue(44100), '44100');
      expect(formatCopiedValue(29.97), '29.97');
    });

    test('时长格式化成 HH:MM:SS.mmm', () {
      expect(formatCopiedValue(44100.0, key: 'duration'), '12:15:00.000');
      expect(formatCopiedValue(1.5, key: 'duration'), '00:00:01.500');
      expect(formatCopiedValue(0.0, key: 'duration'), '00:00:00.000');
    });

    test('带单位的字段复制时不含单位', () {
      expect(formatCopiedValue(44100, unit: 'Hz'), '44100');
      expect(formatCopiedValue(1411200, unit: 'bit/s'), '1411200');
      expect(formatCopiedValue('44100 Hz', unit: 'Hz'), '44100');
    });

    test('字符串原样复制', () {
      expect(formatCopiedValue('PCM'), 'PCM');
      expect(formatCopiedValue('MPEG-1 Layer 3'), 'MPEG-1 Layer 3');
    });

    test('布尔复制为 true / false', () {
      expect(formatCopiedValue(true), 'true');
      expect(formatCopiedValue(false), 'false');
    });

    test('空值复制为空字符串', () {
      expect(formatCopiedValue(null), '');
    });

    test('语义字段按 key 走同一套规则', () {
      const field = SemanticField(
        key: 'duration',
        label: '时长',
        value: 3661.25,
        unit: 's',
      );

      expect(formatCopiedFieldValue(field), '01:01:01.250');
    });

    test('标签值按同一套规则', () {
      const tag = Tag(key: 'TITLE', value: 'Song', source: 'VORBIS_COMMENT');

      expect(formatCopiedTagValue(tag), 'Song');
    });
  });
}
