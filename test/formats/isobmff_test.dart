import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/core/byte_source.dart';
import 'package:media_info/src/core/engine.dart';
import 'package:media_info/src/core/node.dart';
import 'package:media_info/src/core/registry.dart';
import 'package:media_info/src/formats/isobmff.dart';

import '../core/support/memory_byte_source.dart';

/// 素材文件名（相对 test/fixtures/）。
const String mp4 = 'mp4_h264_aac_320x240.normal.mp4';
const String mp4Edge = 'mp4_h264_noaudio_320x240.edge.mp4';
const String mp4Truncated = 'mp4_h264_aac_320x240.normal.truncated.mp4';
const String mov = 'mov_mpeg4_aac_320x240.normal.mov';
const String movTruncated = 'mov_mpeg4_aac_320x240.normal.truncated.mov';

/// 解析整个结构树（moov → trak → mdia → minf → stbl → stsd 共 6 层）。
ParseResult _parse(String name) {
  final source = FileByteSource.fromPath('test/fixtures/$name');
  return parseContainer(isoBmffContainer, source, depth: 8);
}

/// 结构树里出现过的所有块类型。
Set<String> _typesOf(ContainerNode node) {
  final types = <String>{node.type};
  for (final child in node.children) {
    types.addAll(_typesOf(child));
  }
  return types;
}

/// 深度优先找第一个类型为 [type] 的块。
ContainerNode? _find(ContainerNode node, String type) {
  for (final child in node.children) {
    if (child.type == type) return child;
    final found = _find(child, type);
    if (found != null) return found;
  }
  return null;
}

/// 按 key（可选按轨道序号）取语义字段。
SemanticField? _field(
  List<SemanticField> fields,
  String key, {
  int? trackIndex,
}) {
  for (final field in fields) {
    if (field.key != key) continue;
    if (trackIndex != null && field.trackIndex != trackIndex) continue;
    return field;
  }
  return null;
}

void main() {
  group('ISO BMFF（MP4 / MOV）', () {
    test('MP4 结构树覆盖关键块', () {
      final types = _typesOf(_parse(mp4).root);

      // 样本里没有 'skip' / 'uuid' 块（ffmpeg 默认不写），它们由下面的
      // 合成文件用例覆盖。
      expect(
        types,
        containsAll([
          'ftyp',
          'moov',
          'trak',
          'mdia',
          'minf',
          'stbl',
          'stsd',
          'mdat',
          'free',
        ]),
      );
    });

    test('MP4 结构树块类型逐字来自文件', () {
      final root = _parse(mp4).root;

      expect(root.type, 'MP4');
      expect(root.offset, 0);
      expect(root.size, 11658);
      final topTypes = root.children.map((c) => c.type).toList();
      expect(topTypes, containsAll(['ftyp', 'free', 'mdat', 'moov']));
    });

    test('dref 里的 url 数据引用条目在结构树里', () {
      final root = _parse(mp4).root;

      final dref = _find(root, 'dref');
      expect(dref, isNotNull);
      expect(dref!.children.map((c) => c.type).toList(), ['url ']);
    });

    test('MP4 文件级语义字段', () {
      final fields = extractIsoBmffFields(_parse(mp4).root);

      final duration = _field(fields, 'duration')!;
      expect(duration.value, 1.0);
      expect(duration.label, '时长');
      expect(duration.unit, 's');
      expect(duration.scope, FieldScope.file);

      final bitrate = _field(fields, 'overall_bitrate')!;
      expect(bitrate.value, closeTo(93264, 1));
      expect(bitrate.label, '平均码率');
      expect(bitrate.origin, FieldOrigin.derived);

      expect(_field(fields, 'brand')!.value, 'isom');
      expect(_field(fields, 'compatible_brands')!.value, [
        'isom',
        'iso2',
        'avc1',
        'mp41',
      ]);
    });

    test('MP4 视频轨语义字段', () {
      final fields = extractIsoBmffFields(_parse(mp4).root);

      expect(_field(fields, 'track_index', trackIndex: 0)!.value, 0);
      expect(_field(fields, 'track_type', trackIndex: 0)!.value, 'video');
      expect(_field(fields, 'codec', trackIndex: 0)!.value, 'avc1');
      expect(_field(fields, 'width', trackIndex: 0)!.value, 320);
      expect(_field(fields, 'height', trackIndex: 0)!.value, 240);
      expect(_field(fields, 'width', trackIndex: 0)!.unit, 'px');
      expect(_field(fields, 'frame_rate', trackIndex: 0)!.value, 25.0);
      expect(_field(fields, 'frame_rate', trackIndex: 0)!.unit, 'fps');
      expect(_field(fields, 'language', trackIndex: 0)!.value, 'und');
      expect(_field(fields, 'duration', trackIndex: 0)!.value, 1.0);
      expect(
        _field(fields, 'duration', trackIndex: 0)!.scope,
        FieldScope.track,
      );
    });

    test('MP4 音频轨语义字段', () {
      final fields = extractIsoBmffFields(_parse(mp4).root);

      expect(_field(fields, 'track_type', trackIndex: 1)!.value, 'audio');
      expect(_field(fields, 'codec', trackIndex: 1)!.value, 'mp4a');
      expect(_field(fields, 'sample_rate', trackIndex: 1)!.value, 44100);
      expect(_field(fields, 'sample_rate', trackIndex: 1)!.unit, 'Hz');
      expect(_field(fields, 'channels', trackIndex: 1)!.value, 1);
      expect(_field(fields, 'bit_depth', trackIndex: 1)!.value, 16);
      expect(_field(fields, 'bit_depth', trackIndex: 1)!.unit, 'bit');
      expect(_field(fields, 'language', trackIndex: 1)!.value, 'und');
      // 剪辑表把 AAC 编码延迟裁掉后的呈现时长。
      expect(_field(fields, 'duration', trackIndex: 1)!.value, 0.25);
    });

    test('无音轨的 MP4 只有一条视频轨道', () {
      final fields = extractIsoBmffFields(_parse(mp4Edge).root);

      expect(_field(fields, 'duration')!.value, 1.0);
      expect(_field(fields, 'overall_bitrate')!.value, closeTo(67672, 1));
      expect(_field(fields, 'codec', trackIndex: 0)!.value, 'avc1');
      expect(_field(fields, 'track_type', trackIndex: 0)!.value, 'video');
      expect(_field(fields, 'codec', trackIndex: 1), isNull);
      expect(_field(fields, 'sample_rate', trackIndex: 0), isNull);
    });

    test('MOV 结构树与语义字段', () {
      final result = _parse(mov);

      expect(
        _typesOf(result.root),
        containsAll([
          'ftyp',
          'wide',
          'mdat',
          'moov',
          'trak',
          'mdia',
          'minf',
          'stbl',
          'stsd',
        ]),
      );

      final fields = extractIsoBmffFields(result.root);
      expect(_field(fields, 'brand')!.value, 'qt  ');
      expect(_field(fields, 'duration')!.value, 1.0);
      expect(_field(fields, 'overall_bitrate')!.value, closeTo(429248, 1));
      expect(_field(fields, 'codec', trackIndex: 0)!.value, 'mp4v');
      expect(_field(fields, 'width', trackIndex: 0)!.value, 320);
      expect(_field(fields, 'height', trackIndex: 0)!.value, 240);
      expect(_field(fields, 'frame_rate', trackIndex: 0)!.value, 25.0);
      expect(_field(fields, 'codec', trackIndex: 1)!.value, 'mp4a');
      expect(_field(fields, 'sample_rate', trackIndex: 1)!.value, 44100);
      // QuickTime 的语言码是 0x7FFF（未定义）。
      expect(_field(fields, 'language', trackIndex: 0)!.value, 'und');
    });

    test('截断的 MP4 报截断且保留已解析的部分', () {
      final result = _parse(mp4Truncated);

      expect(result.truncated, isTrue);
      expect(result.error, isNotNull);
      final types = _typesOf(result.root);
      expect(types, containsAll(['ftyp', 'free', 'mdat']));
    });

    test('截断的 MOV 报截断且保留已解析的部分', () {
      final result = _parse(movTruncated);

      expect(result.truncated, isTrue);
      expect(result.error, isNotNull);
      expect(_typesOf(result.root), containsAll(['ftyp', 'wide', 'mdat']));
    });

    test('嗅探：ftyp 开头的文件被认成 MP4', () {
      clearFormats();
      addTearDown(clearFormats);
      registerMp4();

      final source = FileByteSource.fromPath('test/fixtures/$mp4');
      expect(detectFormat(source)?.name, 'MP4');
    });

    test('嗅探：扩展名不符也能认出来', () {
      clearFormats();
      addTearDown(clearFormats);
      registerMp4();

      final dir = Directory.systemTemp.createTempSync('media_info_isobmff');
      addTearDown(() => dir.deleteSync(recursive: true));
      final mislabelled = File('${dir.path}/mislabelled.wav')
        ..writeAsBytesSync(File('test/fixtures/$mp4').readAsBytesSync());

      final source = FileByteSource.fromPath(mislabelled.path);
      final detected = detectFormat(source);
      source.close();
      expect(detected?.name, 'MP4');
    });

    test('skip / uuid 块以不透明叶子留在结构树里', () {
      final skip = _box('skip', [0, 0, 0, 0]);
      final uuid = _box('uuid', List<int>.filled(16, 0xAB));
      final ftyp = _box('ftyp', [...'isom'.codeUnits, 0, 0, 0, 0]);
      final source = MemoryByteSource.of([...ftyp, ...skip, ...uuid]);

      final result = parseContainer(isoBmffContainer, source, depth: 8);
      expect(result.truncated, isFalse);

      final types = result.root.children.map((c) => c.type).toList();
      expect(types, containsAll(['ftyp', 'skip', 'uuid']));
      for (final child in result.root.children) {
        if (child.type == 'skip' || child.type == 'uuid') {
          expect(child.isOpaque, isTrue);
        }
      }
    });

    test('stz2：样本大小位宽由载荷决定', () {
      // 位宽 4：一个字节装两个样本大小（高半字节在前）。
      expect(_stz2TotalBytes(4, [1, 2, 3, 15]), 21);
      // 位宽 8：一个字节一个样本大小。
      expect(_stz2TotalBytes(8, [7, 9, 11]), 27);
      // 位宽 16：两个字节一个样本大小。
      expect(_stz2TotalBytes(16, [300, 700]), 1000);
    });
  });
}

/// 造一个只含 `stz2` 的最小 MP4，返回它的字节。
List<int> _stz2File(int fieldSize, List<int> sizes) {
  final entries = <int>[];
  if (fieldSize == 4) {
    for (var i = 0; i < sizes.length; i += 2) {
      final high = sizes[i];
      final low = i + 1 < sizes.length ? sizes[i + 1] : 0;
      entries.add((high << 4) | low);
    }
  } else if (fieldSize == 8) {
    entries.addAll(sizes);
  } else {
    for (final size in sizes) {
      entries.add((size >> 8) & 0xFF);
      entries.add(size & 0xFF);
    }
  }

  final payload = <int>[
    0, 0, 0, 0, // version + flags
    0, 0, 0, // reserved
    fieldSize, //
    (sizes.length >> 16) & 0xFF,
    (sizes.length >> 8) & 0xFF,
    sizes.length & 0xFF,
    ...entries,
  ];

  final stz2 = _box('stz2', payload);
  final stbl = _box('stbl', stz2);
  final minf = _box('minf', stbl);
  final mdia = _box('mdia', minf);
  final trak = _box('trak', mdia);
  final moov = _box('moov', trak);
  final ftyp = _box('ftyp', [...'isom'.codeUnits, 0, 0, 0, 0]);
  return [...ftyp, ...moov];
}

/// `stz2` 样本大小总和（通过公开 API 解析出来的语义字段）。
int _stz2TotalBytes(int fieldSize, List<int> sizes) {
  final source = MemoryByteSource.of(_stz2File(fieldSize, sizes));
  final result = parseContainer(isoBmffContainer, source, depth: 8);
  expect(result.truncated, isFalse);

  final fields = extractIsoBmffFields(result.root);
  final total = _field(fields, 'sample_size_total', trackIndex: 0);
  expect(total, isNotNull);
  expect(_field(fields, 'sample_size_field', trackIndex: 0)!.value, fieldSize);
  expect(_field(fields, 'sample_count', trackIndex: 0)!.value, sizes.length);
  return total!.value as int;
}

/// 造一个 box：size(4) + type(4) + payload。
List<int> _box(String type, List<int> payload) {
  final size = payload.length + 8;
  return [
    (size >> 24) & 0xFF,
    (size >> 16) & 0xFF,
    (size >> 8) & 0xFF,
    size & 0xFF,
    ...type.codeUnits,
    ...payload,
  ];
}
