/// 标签提取的测试：MP4 `ilst`、FLAC Vorbis Comment、MP3 ID3v2。
///
/// 素材（`test/fixtures/`）里 ffmpeg 默认会写一点标签（`©too` / `encoder` /
/// `TSSE`），但只有一条、也解不出封面这种二进制值，所以这里**在测试里现造**
/// 带标签的文件（用 `tool/gen_fixtures.dart` 同款手法写最小字节序列）。
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/core/byte_source.dart';
import 'package:media_info/src/core/engine.dart';
import 'package:media_info/src/core/node.dart';
import 'package:media_info/src/core/tag.dart';
import 'package:media_info/src/formats/flac.dart';
import 'package:media_info/src/formats/isobmff.dart';
import 'package:media_info/src/formats/mp3.dart';
import 'package:media_info/src/formats/riff.dart';

import '../core/support/byte_fixtures.dart';
import '../core/support/memory_byte_source.dart';

void main() {
  group('真实素材', () {
    test('没有标签的 WAV 返回空列表', () {
      final source = FileByteSource.fromPath(
        'test/fixtures/wav_pcm_s16le_44100_stereo.normal.wav',
      );
      addTearDown(source.close);

      final root = parseWav(source).root;

      expect(collectTags(root, source: source), isEmpty);
    });

    test('MP4：ilst 里的标签被解出来', () {
      final source = FileByteSource.fromPath(
        'test/fixtures/mp4_h264_aac_320x240.normal.mp4',
      );
      addTearDown(source.close);

      final root = parseContainer(isoBmffContainer, source, depth: 8).root;
      final tags = collectTags(root, source: source);

      final too = _tag(tags, '©too');
      expect(too, isNotNull);
      expect(too!.value, 'Lavf61.3.104');
      expect(too.source, 'ilst');
    });

    test('FLAC：Vorbis Comment 的 KEY=VALUE 被解出来', () {
      final source = FileByteSource.fromPath(
        'test/fixtures/flac_s16_44100_stereo.normal.flac',
      );
      addTearDown(source.close);

      final root = parseFlac(source).root;
      final tags = collectTags(root, source: source);

      final encoder = _tag(tags, 'encoder');
      expect(encoder, isNotNull);
      expect(encoder!.value, 'Lavf61.3.104');
      expect(encoder.source, 'VORBIS_COMMENT');

      final vendor = _tag(tags, 'vendor');
      expect(vendor, isNotNull);
      expect(vendor!.value, 'Lavf61.3.104');
    });

    test('MP3：ID3v2 文本帧被解出来', () {
      final source = FileByteSource.fromPath(
        'test/fixtures/mp3_cbr128_44100_stereo.normal.mp3',
      );
      addTearDown(source.close);

      final root = parseMp3(source).root;
      final tags = collectTags(root, source: source);

      final tsse = _tag(tags, 'TSSE');
      expect(tsse, isNotNull);
      expect(tsse!.value, 'Lavf61.3.104');
      expect(tsse.source, 'ID3v2');
    });

    test('截断的素材不抛异常', () {
      for (final name in const [
        'mp4_h264_aac_320x240.normal.truncated.mp4',
        'mp3_cbr128_44100_stereo.normal.truncated.mp3',
        'flac_s16_44100_stereo.normal.truncated.flac',
      ]) {
        final source = FileByteSource.fromPath('test/fixtures/$name');
        final root = _rootOf(name, source);
        expect(() => collectTags(root, source: source), returnsNormally);
        source.close();
      }
    });
  });

  group('MP4 标签（合成样本）', () {
    test('文本标签、封面二进制与 trkn 都被解出来', () {
      final cover = <int>[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46];
      final source = MemoryByteSource.of(
        _mp4File([
          _box('©nam', _dataBox(1, utf8('标题'))),
          _box('©ART', _dataBox(1, utf8('艺术家'))),
          _box('©alb', _dataBox(1, utf8('专辑'))),
          _box('covr', _dataBox(13, cover)),
          _box('trkn', _dataBox(0, [0, 0, 0, 3, 0, 12, 0, 0])),
        ]),
      );

      final tags = collectTags(_mp4Root(source), source: source);

      expect(_tag(tags, '©nam')!.value, '标题');
      expect(_tag(tags, '©ART')!.value, '艺术家');
      expect(_tag(tags, '©alb')!.value, '专辑');
      expect(_tag(tags, '©nam')!.source, 'ilst');

      final coverTag = _tag(tags, 'covr');
      expect(coverTag, isNotNull);
      expect(coverTag!.value, isA<Uint8List>());
      expect(coverTag.value as Uint8List, cover);

      expect(_tag(tags, 'trkn')!.value, '3/12');
    });

    test('key 保留英文原名，不翻译', () {
      final source = MemoryByteSource.of(
        _mp4File([_box('©nam', _dataBox(1, utf8('标题')))]),
      );

      final tags = collectTags(_mp4Root(source), source: source);

      expect(tags.map((t) => t.key), contains('©nam'));
      expect(tags.map((t) => t.key), isNot(contains('标题')));
    });

    test('坏的 item 被跳过，其它标签照常解出来', () {
      final source = MemoryByteSource.of(
        _mp4File([
          // `data` 盒的载荷不足 8 字节（没有 type + locale）→ 跳过。
          _box('©bad', _box('data', [1, 2, 3])),
          _box('©nam', _dataBox(1, utf8('标题'))),
        ]),
      );

      final tags = collectTags(_mp4Root(source), source: source);

      expect(_tag(tags, '©bad'), isNull);
      expect(_tag(tags, '©nam')!.value, '标题');
    });

    test('没有 data 盒的 item 不产生标签', () {
      final source = MemoryByteSource.of(
        _mp4File([_box('©nam', _box('mean', utf8('com.apple.iTunes')))]),
      );

      final tags = collectTags(_mp4Root(source), source: source);

      expect(tags, isEmpty);
    });

    test('树里没有 `udta` 时返回空列表', () {
      final source = MemoryByteSource.of(
        _box('ftyp', [...ascii('isom'), 0, 0, 0, 0]),
      );

      final tags = collectTags(_mp4Root(source), source: source);

      expect(tags, isEmpty);
    });

    test('结构树只展开一层（只看得到 `moov`）时也能解出标签', () {
      final source = MemoryByteSource.of(
        _mp4File([_box('©nam', _dataBox(1, utf8('标题')))]),
      );
      final root = parseContainer(isoBmffContainer, source, depth: 1).root;

      final tags = collectTags(root, source: source);

      expect(_tag(tags, '©nam')!.value, '标题');
    });

    test('同一份 `ilst` 只解一次（不重复）', () {
      final source = MemoryByteSource.of(
        _mp4File([_box('©nam', _dataBox(1, utf8('标题')))]),
      );

      final tags = collectTags(_mp4Root(source), source: source);

      expect(tags.where((t) => t.key == '©nam').length, 1);
    });
  });

  group('FLAC 标签（合成样本）', () {
    test('多个 KEY=VALUE 被解出来', () {
      final source = MemoryByteSource.of(_flacFile(['TITLE=标题', 'ARTIST=艺术家']));

      final tags = collectTags(_flacRoot(source), source: source);

      expect(_tag(tags, 'TITLE')!.value, '标题');
      expect(_tag(tags, 'ARTIST')!.value, '艺术家');
      expect(_tag(tags, 'TITLE')!.source, 'VORBIS_COMMENT');
      expect(_tag(tags, 'vendor')!.value, 'test-vendor');
    });

    test('没有 = 的条目被跳过', () {
      final source = MemoryByteSource.of(_flacFile(['BROKEN', 'TITLE=标题']));

      final tags = collectTags(_flacRoot(source), source: source);

      expect(_tag(tags, 'BROKEN'), isNull);
      expect(_tag(tags, 'TITLE')!.value, '标题');
    });

    test('长度撒谎的注释块被截断，不抛异常', () {
      final source = MemoryByteSource.of(_flacFile(['TITLE=标题']));
      // 把 vendor 长度改成超大值：后面的注释都读不出来。
      final broken = Uint8List.fromList(source.bytes);
      broken[8] = 0xFF;
      broken[9] = 0xFF;

      final brokenSource = MemoryByteSource(broken);

      expect(
        () => collectTags(_flacRoot(brokenSource), source: brokenSource),
        returnsNormally,
      );
    });
  });

  group('MP3 标签（合成样本）', () {
    test('ID3v2.3 的文本帧被解出来（帧大小是普通整数）', () {
      final source = MemoryByteSource.of(
        _id3File(3, [
          _id3Frame('TIT2', [3, ...utf8('标题')]),
          _id3Frame('TPE1', [3, ...utf8('艺术家')]),
        ]),
      );

      final tags = collectTags(_mp3Root(source), source: source);

      expect(_tag(tags, 'TIT2')!.value, '标题');
      expect(_tag(tags, 'TPE1')!.value, '艺术家');
      expect(_tag(tags, 'TIT2')!.source, 'ID3v2');
    });

    test('ID3v2.4 的文本帧被解出来（帧大小是 syncsafe 整数）', () {
      final source = MemoryByteSource.of(
        _id3File(4, [
          _id3Frame('TIT2', [3, ...utf8('标题')], syncsafe: true),
        ]),
      );

      final tags = collectTags(_mp3Root(source), source: source);

      expect(_tag(tags, 'TIT2')!.value, '标题');
    });

    test('非文本帧被跳过', () {
      final source = MemoryByteSource.of(
        _id3File(4, [
          _id3Frame('APIC', [0, 0xFF, 0xD8, 0xFF], syncsafe: true),
          _id3Frame('TIT2', [3, ...utf8('标题')], syncsafe: true),
        ]),
      );

      final tags = collectTags(_mp3Root(source), source: source);

      expect(_tag(tags, 'APIC'), isNull);
      expect(_tag(tags, 'TIT2')!.value, '标题');
    });

    test('ID3v2.2（3 字节帧 ID）不被支持，返回空列表', () {
      final source = MemoryByteSource.of(
        _id3File(2, [
          _id3Frame('TIT2', [3, ...utf8('标题')]),
        ]),
      );

      final tags = collectTags(_mp3Root(source), source: source);

      expect(tags, isEmpty);
    });
  });

  group('容错', () {
    test('不给字节源时返回空列表', () {
      final source = MemoryByteSource.of(_flacFile(['TITLE=标题']));

      expect(collectTags(_flacRoot(source)), isEmpty);
    });

    test('垃圾数据不抛异常', () {
      final source = MemoryByteSource.of(List<int>.filled(64, 0xAB));

      expect(
        () => collectTags(_flacRoot(source), source: source),
        returnsNormally,
      );
    });
  });
}

// ---------------------------------------------------------------------------
// 断言辅助
// ---------------------------------------------------------------------------

/// 按 key 取第一个标签。
Tag? _tag(List<Tag> tags, String key) {
  for (final tag in tags) {
    if (tag.key == key) return tag;
  }
  return null;
}

/// 按文件名选解析器（截断素材用）。
ContainerNode _rootOf(String name, ByteSource source) {
  if (name.endsWith('.mp4')) {
    return parseContainer(isoBmffContainer, source, depth: 8).root;
  }
  if (name.endsWith('.mp3')) return parseMp3(source).root;
  return parseFlac(source).root;
}

// ---------------------------------------------------------------------------
// 合成素材
// ---------------------------------------------------------------------------

/// 造一个盒：size(4) + type(4) + 载荷。
List<int> _box(String type, List<int> payload) {
  final size = payload.length + 8;
  return [...u32be(size), ...ascii(type), ...payload];
}

/// 造一个 `data` 盒：type 码(1) + 保留(3) + locale(4) + 值。
List<int> _dataBox(int typeCode, List<int> value) =>
    _box('data', [typeCode, 0, 0, 0, ...u32be(0), ...value]);

/// 造一个带 `ilst` 的最小 MP4：`ftyp` + `moov` → `udta` → `meta` → `ilst`。
List<int> _mp4File(List<List<int>> items) {
  final ilst = _box('ilst', concat(items));
  final meta = _box('meta', [0, 0, 0, 0, ...ilst]);
  final udta = _box('udta', meta);
  final moov = _box('moov', udta);
  final ftyp = _box('ftyp', [...ascii('isom'), 0, 0, 0, 0]);
  return [...ftyp, ...moov];
}

/// 解析一个合成 MP4 的结构树。
ContainerNode _mp4Root(ByteSource source) =>
    parseContainer(isoBmffContainer, source, depth: 8).root;

/// 造一个带 Vorbis Comment 的最小 FLAC。
List<int> _flacFile(List<String> comments, {String vendor = 'test-vendor'}) {
  final vendorBytes = utf8(vendor);
  final entries = <int>[];
  for (final comment in comments) {
    final bytes = utf8(comment);
    entries.addAll(u32le(bytes.length));
    entries.addAll(bytes);
  }
  final payload = <int>[
    ...u32le(vendorBytes.length),
    ...vendorBytes,
    ...u32le(comments.length),
    ...entries,
  ];
  final header = <int>[
    0x84, // 最后一个元数据块 + 类型 4（VORBIS_COMMENT）
    (payload.length >> 16) & 0xFF,
    (payload.length >> 8) & 0xFF,
    payload.length & 0xFF,
  ];
  return [...ascii('fLaC'), ...header, ...payload];
}

/// 解析一个合成 FLAC 的结构树。
ContainerNode _flacRoot(ByteSource source) => parseFlac(source).root;

/// 解析一个合成 MP3 的结构树。
ContainerNode _mp3Root(ByteSource source) => parseMp3(source).root;

/// 造一个只有 ID3v2 标签的最小 MP3（后面补几字节，避免标签被截断）。
List<int> _id3File(int major, List<List<int>> frames) {
  final body = concat(frames);
  return [
    ...ascii('ID3'),
    major,
    0,
    0,
    ..._syncsafeBytes(body.length),
    ...body,
    0,
    0,
    0,
    0,
  ];
}

/// 造一个 ID3 帧：ID(4) + 大小(4) + 标志(2) + 帧体。
List<int> _id3Frame(String id, List<int> body, {bool syncsafe = false}) {
  final size = syncsafe ? _syncsafeBytes(body.length) : u32be(body.length);
  return [...ascii(id), ...size, 0, 0, ...body];
}

/// syncsafe 整数（每字节只用 7 位）。
List<int> _syncsafeBytes(int value) => [
  (value >> 21) & 0x7F,
  (value >> 14) & 0x7F,
  (value >> 7) & 0x7F,
  value & 0x7F,
];
