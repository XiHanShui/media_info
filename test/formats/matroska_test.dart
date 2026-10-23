import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/core/byte_source.dart';
import 'package:media_info/src/core/engine.dart';
import 'package:media_info/src/core/node.dart';
import 'package:media_info/src/core/registry.dart';
import 'package:media_info/src/formats/matroska.dart';
import 'package:media_info/src/formats/matroska_schema.dart';

import '../core/support/memory_byte_source.dart';

/// 结构树里所有节点（含自身）的元素 ID。
Set<String> _allIds(ContainerNode node) {
  final out = <String>{node.type};
  for (final child in node.children) {
    out.addAll(_allIds(child));
  }
  return out;
}

/// 深度优先找第一个匹配的元素 ID。
ContainerNode? _find(ContainerNode node, String id) {
  if (node.type == id) return node;
  for (final child in node.children) {
    final found = _find(child, id);
    if (found != null) return found;
  }
  return null;
}

/// 深度优先找所有匹配的元素 ID。
List<ContainerNode> _findAll(ContainerNode node, String id) {
  final out = <ContainerNode>[];
  if (node.type == id) out.add(node);
  for (final child in node.children) {
    out.addAll(_findAll(child, id));
  }
  return out;
}

/// 语义字段里某个 key 的值。
Object? _value(List<SemanticField> fields, String key) {
  for (final field in fields) {
    if (field.key == key) return field.value;
  }
  return null;
}

FileByteSource _fixture(String name) =>
    FileByteSource.fromPath('test/fixtures/$name');

/// 最短编码的 EBML 变长整数。
List<int> _vint(int value) {
  for (var width = 1; width <= 8; width++) {
    final max = (1 << (7 * width)) - 1;
    if (value >= max) continue;
    final bytes = <int>[];
    var rest = value;
    for (var i = 0; i < width; i++) {
      bytes.insert(0, rest & 0xFF);
      rest >>= 8;
    }
    bytes[0] |= 1 << (8 - width);
    return bytes;
  }
  throw ArgumentError('值太大：$value');
}

/// 一个 EBML 元素（ID 字节 + 长度 VINT + 载荷）。
List<int> _element(List<int> id, List<int> payload) => <int>[
  ...id,
  ..._vint(payload.length),
  ...payload,
];

/// 8 字节大端浮点数。
List<int> _float64(double value) =>
    (ByteData(8)..setFloat64(0, value, Endian.big)).buffer.asUint8List();

void main() {
  group('EBML 规格表', () {
    test('包含官方 schema 的 262 个元素与 RFC 8794 的 EBML 头元素', () {
      expect(matroskaSchemaElements.length, 270);
      expect(
        matroskaSchemaElements.where((e) => e.type == EbmlElementType.master),
        hasLength(50),
      );
    });

    test('包含必需的 master 元素', () {
      const required = <String>[
        'EBML',
        'Segment',
        'SeekHead',
        'Info',
        'Tracks',
        'TrackEntry',
        'Video',
        'Audio',
        'Cluster',
        'Tags',
        'BlockGroup',
      ];
      for (final name in required) {
        final element = matroskaSchemaElements.firstWhere(
          (e) => e.name == name,
          orElse: () => fail('规格表里缺少 $name'),
        );
        expect(element.isMaster, isTrue, reason: '$name 应该是 master 元素');
      }
    });

    test('保留 WebM 子集标记', () {
      expect(matroskaSchemaElements.where((e) => e.webm), hasLength(134));
      expect(matroskaElement('0x18538067')!.webm, isTrue);
      expect(matroskaElement('0xE1')!.webm, isTrue);
    });

    test('元素 ID 是最短编码的十六进制文本，且与核心引擎的节点 type 同形', () {
      for (final element in matroskaSchemaElements) {
        expect(
          element.id,
          matches(RegExp(r'^0x[0-9A-F]{2,8}$')),
          reason: '${element.name} 的 ID 不合法',
        );
        expect(element.id.length.isEven, isTrue, reason: element.name);
        expect(element.path, startsWith(r'\'), reason: element.name);
      }
    });

    test('标记出允许未知长度的元素（收尾靠路径判定）', () {
      expect(matroskaElement('0x18538067')!.unknownSizeAllowed, isTrue);
      expect(matroskaElement('0x1F43B675')!.unknownSizeAllowed, isTrue);
      expect(matroskaElement('0x1549A966')!.unknownSizeAllowed, isFalse);
    });
  });

  group('结构树', () {
    test('MKV 样本能解析出 Segment/Info/Tracks/TrackEntry/Video/Audio', () {
      final source = _fixture('mkv_vp9_opus_320x240.normal.mkv');
      addTearDown(source.close);

      final result = parseContainer(matroskaFormat.container, source, depth: 6);

      expect(result.truncated, isFalse);
      expect(result.error, isNull);
      final ids = _allIds(result.root);
      expect(ids, contains('0x18538067')); // Segment
      expect(ids, contains('0x1549A966')); // Info
      expect(ids, contains('0x1654AE6B')); // Tracks
      expect(ids, contains('0xAE')); // TrackEntry
      expect(ids, contains('0xE0')); // Video
      expect(ids, contains('0xE1')); // Audio
    });

    test('SimpleBlock 是不透明叶子（4 种 lacing 不可表驱动）', () {
      final source = _fixture('mkv_vp9_opus_320x240.normal.mkv');
      addTearDown(source.close);

      final result = parseContainer(matroskaFormat.container, source, depth: 6);

      final blocks = _findAll(result.root, '0xA3');
      expect(blocks, isNotEmpty);
      expect(blocks.first.isOpaque, isTrue);
      expect(blocks.first.children, isEmpty);
    });

    test('无音轨样本优雅处理：没有 Audio 元素', () {
      final source = _fixture('mkv_vp9_noaudio_320x240.edge.mkv');
      addTearDown(source.close);

      final result = parseContainer(matroskaFormat.container, source, depth: 6);

      expect(result.truncated, isFalse);
      final ids = _allIds(result.root);
      expect(ids, contains('0xE0')); // Video
      expect(ids, isNot(contains('0xE1'))); // Audio
    });

    test('未知长度的 Segment 按路径收尾，一直吃到文件末尾', () {
      // 手工拼一个"未知长度 Segment"的最小文件：EBML 头 + Segment(未知长度) + Info。
      final info = _element(
        <int>[0x15, 0x49, 0xA9, 0x66],
        <int>[
          ..._element(<int>[0x2A, 0xD7, 0xB1], <int>[0x0F, 0x42, 0x40]),
        ],
      );
      final segment = <int>[
        0x18, 0x53, 0x80, 0x67,
        0xFF, // 未知长度哨兵：长度 VINT 的数据位全 1
        ...info,
      ];
      final header = _element(
        <int>[0x1A, 0x45, 0xDF, 0xA3],
        <int>[
          ..._element(<int>[0x42, 0x86], <int>[0x01]),
          ..._element(<int>[0x42, 0x82], ascii.encode('matroska')),
        ],
      );
      final bytes = Uint8List.fromList(<int>[...header, ...segment]);

      final result = parseContainer(
        matroskaFormat.container,
        MemoryByteSource(bytes),
        depth: 4,
      );

      expect(result.truncated, isFalse);
      final segmentNode = _find(result.root, '0x18538067');
      expect(segmentNode, isNotNull);
      expect(segmentNode!.isOpaque, isFalse);
      // 未知长度 → 载荷延伸到区域（这里是文件）末尾。
      expect(segmentNode.dataOffset + segmentNode.dataSize, bytes.length);
      expect(_find(result.root, '0x1549A966'), isNotNull);
    });

    test('截断样本不抛异常：报截断且已解析的部分照常返回', () {
      final source = _fixture('mkv_vp9_opus_320x240.normal.truncated.mkv');
      addTearDown(source.close);

      final result = parseContainer(matroskaFormat.container, source, depth: 6);

      expect(result.truncated, isTrue);
      expect(result.error, isNotNull);
      expect(result.error, contains('截断'));
      // EBML 头在文件开头，一定解析得出来。
      expect(_find(result.root, '0x1A45DFA3'), isNotNull);
    });

    test('结构树视图可以按 schema 解码叶子元素的值', () {
      final source = _fixture('mkv_vp9_opus_320x240.normal.mkv');
      addTearDown(source.close);

      final result = parseContainer(matroskaFormat.container, source, depth: 6);

      expect(matroskaElementName('0x86'), 'CodecID');
      expect(decodeMatroskaValue(_find(result.root, '0x86')!), 'V_VP9');
      expect(decodeMatroskaValue(_find(result.root, '0xB0')!), 320);
      expect(decodeMatroskaValue(_find(result.root, '0xB5')!), 48000.0);
    });
  });

  group('语义字段', () {
    test('MKV 样本：时长/编码/分辨率/采样率/声道数/轨道类型', () {
      final source = _fixture('mkv_vp9_opus_320x240.normal.mkv');
      addTearDown(source.close);

      final result = parseContainer(matroskaFormat.container, source, depth: 6);
      final fields = extractMatroskaFields(result.root);

      expect(_value(fields, 'duration'), closeTo(1.0, 0.05));
      expect(_value(fields, 'container_format'), 'matroska');
      expect(_value(fields, 'file_size'), source.length);
      expect(_value(fields, 'overall_bitrate'), closeTo(139896, 2000));

      final semantics = extractMatroskaSemantics(result.root);
      expect(semantics.tracks, hasLength(2));

      final video = semantics.tracks[0];
      expect(video.node.type, '0xAE'); // TrackEntry
      expect(_value(video.fields, 'track_type'), 'video');
      expect(_value(video.fields, 'codec'), 'V_VP9');
      expect(_value(video.fields, 'width'), 320);
      expect(_value(video.fields, 'height'), 240);

      final audio = semantics.tracks[1];
      expect(audio.node.type, '0xAE');
      expect(_value(audio.fields, 'track_type'), 'audio');
      expect(_value(audio.fields, 'codec'), 'A_OPUS');
      expect(_value(audio.fields, 'sample_rate'), 48000);
      expect(_value(audio.fields, 'channels'), 1);
    });

    test('轨道级字段作用域是 track，文件级字段作用域是 file', () {
      final source = _fixture('mkv_vp9_opus_320x240.normal.mkv');
      addTearDown(source.close);

      final result = parseContainer(matroskaFormat.container, source, depth: 6);
      final semantics = extractMatroskaSemantics(result.root);

      expect(semantics.tracks.first.fields.first.scope, FieldScope.track);
      expect(semantics.tracks.first.fields.first.trackIndex, 0);
      expect(semantics.tracks[1].fields.first.trackIndex, 1);
      expect(semantics.fileFields, isNotEmpty);
      expect(
        semantics.fileFields.every((f) => f.scope == FieldScope.file),
        isTrue,
      );
    });

    test('语义字段带中文显示名', () {
      final source = _fixture('mkv_vp9_opus_320x240.normal.mkv');
      addTearDown(source.close);

      final result = parseContainer(matroskaFormat.container, source, depth: 6);
      final labels = <String, String>{
        for (final field in extractMatroskaFields(result.root))
          field.key: field.label,
      };

      expect(labels['duration'], '时长');
      expect(labels['codec'], '编码标识');
      expect(labels['width'], '宽度');
      expect(labels['height'], '高度');
      expect(labels['sample_rate'], '采样率');
      expect(labels['channels'], '声道数');
      expect(labels['bit_depth'], '位深');
      expect(labels['track_type'], '轨道类型');
      expect(labels['overall_bitrate'], '平均码率');
    });

    test('WebM 样本：容器格式是 WebM，编码/采样率照读', () {
      final source = _fixture('webm_vp8_vorbis_320x240.normal.webm');
      addTearDown(source.close);

      final result = parseContainer(matroskaFormat.container, source, depth: 6);
      final semantics = extractMatroskaSemantics(result.root);

      expect(_value(semantics.fileFields, 'container_format'), 'webm');
      expect(_value(semantics.fileFields, 'duration'), closeTo(1.003, 0.05));
      expect(_value(semantics.tracks[0].fields, 'codec'), 'V_VP8');
      expect(_value(semantics.tracks[0].fields, 'width'), 320);
      expect(_value(semantics.tracks[1].fields, 'codec'), 'A_VORBIS');
      expect(_value(semantics.tracks[1].fields, 'sample_rate'), 44100);
    });

    test('无音轨样本不产出采样率/声道数字段', () {
      final source = _fixture('mkv_vp9_noaudio_320x240.edge.mkv');
      addTearDown(source.close);

      final result = parseContainer(matroskaFormat.container, source, depth: 6);
      final semantics = extractMatroskaSemantics(result.root);

      expect(semantics.tracks, hasLength(1));
      expect(_value(semantics.tracks.single.fields, 'sample_rate'), isNull);
      expect(_value(semantics.tracks.single.fields, 'channels'), isNull);
      expect(_value(semantics.tracks.single.fields, 'codec'), 'V_VP9');
    });

    test('截断样本上提取器不抛异常', () {
      final source = _fixture('mkv_vp9_opus_320x240.normal.truncated.mkv');
      addTearDown(source.close);

      final result = parseContainer(matroskaFormat.container, source, depth: 6);

      expect(() => extractMatroskaFields(result.root), returnsNormally);
    });

    test('人工构造的文件能读出位深等字段（解码路径全覆盖）', () {
      final audio = _element(
        <int>[0xE1],
        <int>[
          ..._element(<int>[0xB5], _float64(44100)), // SamplingFrequency
          ..._element(<int>[0x9F], <int>[0x02]), // Channels
          ..._element(<int>[0x62, 0x64], <int>[0x10]), // BitDepth = 16
        ],
      );
      final trackEntry = _element(
        <int>[0xAE],
        <int>[
          ..._element(<int>[0x83], <int>[0x02]), // TrackType = 2（audio）
          ..._element(<int>[0x86], ascii.encode('A_OPUS')),
          ...audio,
        ],
      );
      final tracks = _element(<int>[0x16, 0x54, 0xAE, 0x6B], trackEntry);
      final info = _element(
        <int>[0x15, 0x49, 0xA9, 0x66],
        <int>[
          ..._element(<int>[0x2A, 0xD7, 0xB1], <int>[0x0F, 0x42, 0x40]),
          ..._element(<int>[0x44, 0x89], _float64(2000)), // Duration = 2000 刻
        ],
      );
      final segment = <int>[
        0x18,
        0x53,
        0x80,
        0x67,
        ..._vint(info.length + tracks.length),
        ...info,
        ...tracks,
      ];
      final header = _element(
        <int>[0x1A, 0x45, 0xDF, 0xA3],
        <int>[
          ..._element(<int>[0x42, 0x82], ascii.encode('matroska')),
        ],
      );
      final bytes = Uint8List.fromList(<int>[...header, ...segment]);

      final result = parseContainer(
        matroskaFormat.container,
        MemoryByteSource(bytes),
        depth: 6,
      );
      final semantics = extractMatroskaSemantics(result.root);

      // 2000 刻 × 1 000 000 ns = 2 秒。
      expect(_value(semantics.fileFields, 'duration'), closeTo(2.0, 0.0001));
      expect(_value(semantics.fileFields, 'timestamp_scale'), 1000000);
      expect(semantics.tracks, hasLength(1));
      final track = semantics.tracks.single;
      expect(_value(track.fields, 'track_type'), 'audio');
      expect(_value(track.fields, 'codec'), 'A_OPUS');
      expect(_value(track.fields, 'sample_rate'), 44100);
      expect(_value(track.fields, 'channels'), 2);
      expect(_value(track.fields, 'bit_depth'), 16);
    });
  });

  group('注册表', () {
    test('注册后能被内容嗅探识别', () {
      registerMatroska();
      final source = _fixture('webm_vp8_vorbis_320x240.normal.webm');
      addTearDown(source.close);

      final detected = detectFormat(source);
      expect(detected, isNotNull);
      expect(detected!.name, matroskaFormat.name);
    });

    test('不是 EBML 的文件不会被认成 Matroska', () {
      final source = _fixture('wav_pcm_s16le_44100_stereo.normal.wav');
      addTearDown(source.close);

      expect(matroskaFormat.detect!(source), isFalse);
    });
  });
}
