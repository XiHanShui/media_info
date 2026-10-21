import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/core/byte_source.dart';
import 'package:media_info/src/core/errors.dart';
import 'package:media_info/src/core/registry.dart';
import 'package:media_info/src/formats/flac.dart';
import 'package:media_info/src/formats/isobmff.dart';
import 'package:media_info/src/formats/matroska.dart';
import 'package:media_info/src/formats/mp3.dart';
import 'package:media_info/src/formats/riff.dart';

/// 素材路径（相对 test/fixtures/）。
String _fixture(String name) => 'test/fixtures/$name';

/// 嗅探用例表：素材 -> 期望被认出的格式名。
///
/// 表里同时包含 `.normal` / `.edge` / `.truncated` 三类素材：
/// 截断的素材文件头还在，嗅探只看头，所以照样要认得出来。
const List<({String fixture, String format})>
_cases = <({String fixture, String format})>[
  // --- WAV ---
  (fixture: 'wav_pcm_s16le_44100_stereo.normal.wav', format: 'WAV'),
  (fixture: 'wav_pcm_s16le_44100_stereo.normal.truncated.wav', format: 'WAV'),
  (fixture: 'wav_pcm_s16le_44100_stereo.normal.liesize.wav', format: 'WAV'),
  (fixture: 'wav_pcm_s24le_48000_stereo.edge.wav', format: 'WAV'),
  (fixture: 'wav_pcm_u8_8000_mono.edge.wav', format: 'WAV'),
  // --- AIFF ---
  (fixture: 'aiff_pcm_s16be_48000_mono.normal.aiff', format: 'AIFF'),
  (fixture: 'aiff_pcm_s16be_48000_mono.normal.truncated.aiff', format: 'AIFF'),
  (fixture: 'aiff_pcm_s24be_44100_stereo.edge.aiff', format: 'AIFF'),
  // --- MP4 / MOV（同一个容器，同一个格式项）---
  (fixture: 'mp4_h264_aac_320x240.normal.mp4', format: 'MP4'),
  (fixture: 'mp4_h264_aac_320x240.normal.truncated.mp4', format: 'MP4'),
  (fixture: 'mp4_h264_noaudio_320x240.edge.mp4', format: 'MP4'),
  (fixture: 'mov_mpeg4_aac_320x240.normal.mov', format: 'MP4'),
  (fixture: 'mov_mpeg4_aac_320x240.normal.truncated.mov', format: 'MP4'),
  // --- FLAC ---
  (fixture: 'flac_s16_44100_stereo.normal.flac', format: 'FLAC'),
  (fixture: 'flac_s16_44100_stereo.normal.truncated.flac', format: 'FLAC'),
  (fixture: 'flac_s24_96000_mono.edge.flac', format: 'FLAC'),
  // --- Matroska / WebM（同一个容器，同一个格式项）---
  (fixture: 'mkv_vp9_opus_320x240.normal.mkv', format: 'Matroska'),
  (fixture: 'mkv_vp9_opus_320x240.normal.truncated.mkv', format: 'Matroska'),
  (fixture: 'mkv_vp9_noaudio_320x240.edge.mkv', format: 'Matroska'),
  (fixture: 'webm_vp8_vorbis_320x240.normal.webm', format: 'Matroska'),
  (
    fixture: 'webm_vp8_vorbis_320x240.normal.truncated.webm',
    format: 'Matroska',
  ),
  // --- MP3 ---
  (fixture: 'mp3_cbr128_44100_stereo.normal.mp3', format: 'MP3'),
  (fixture: 'mp3_cbr128_44100_stereo.normal.truncated.mp3', format: 'MP3'),
  (fixture: 'mp3_vbr_q2_22050_mono.edge.mp3', format: 'MP3'),
];

/// 嗅探一个文件，返回命中的格式名；认不出来返回 null。
String? _detectName(String path) {
  final source = FileByteSource.fromPath(path);
  try {
    return detectFormat(source)?.name;
  } finally {
    source.close();
  }
}

/// 某个格式的 detect 是否认这个文件。
///
/// 读不到魔数（文件太短）不算命中——与注册表 `detectFormat` 的约定一致。
bool _claims(FormatSpec spec, String path) {
  final detect = spec.detect;
  if (detect == null) return false;
  final source = FileByteSource.fromPath(path);
  try {
    return detect(source);
  } on TruncatedFile {
    return false;
  } finally {
    source.close();
  }
}

/// 解析素材并取某个语义字段的值。
Object? _semanticValue(String fixture, String key) {
  final path = _fixture(fixture);
  final source = FileByteSource.fromPath(path);
  try {
    final spec = detectFormat(source);
    if (spec == null) return null;
    final extractor = spec.extractor;
    if (extractor == null) return null;
    final result = parseFormat(spec, source, depth: 4);
    for (final field in extractor(result.root)) {
      if (field.key == key) return field.value;
    }
    return null;
  } finally {
    source.close();
  }
}

/// 记录读取量的字节源：用来验证 detect 只读文件头。
class _CountingByteSource implements ByteSource {
  _CountingByteSource(this._inner);

  final ByteSource _inner;

  /// 一共读了多少字节。
  int bytesRead = 0;

  /// 读到的最远位置（不含）。
  int maxEnd = 0;

  void close() {
    final inner = _inner;
    if (inner is FileByteSource) inner.close();
  }

  @override
  int get length => _inner.length;

  @override
  Uint8List read(int offset, int length) {
    final bytes = _inner.read(offset, length);
    bytesRead += bytes.length;
    final end = offset + bytes.length;
    if (end > maxEnd) maxEnd = end;
    return bytes;
  }
}

/// 在临时目录里写一个文件，返回路径（临时目录在测试结束时删掉）。
String _writeTempFile(String name, List<int> bytes) {
  final dir = Directory.systemTemp.createTempSync('media_info_detect');
  addTearDown(() => dir.deleteSync(recursive: true));
  final file = File('${dir.path}/$name')..writeAsBytesSync(bytes);
  return file.path;
}

/// 什么都认的测试替身：用来验证"注册顺序即嗅探顺序"。
FormatSpec _alwaysMatches(String name) =>
    FormatSpec(name: name, container: wavFormat.container, detect: (_) => true);

void main() {
  setUp(() {
    clearFormats();
    // 注册顺序 = 嗅探顺序。测试依赖这个顺序，所以写死在这里。
    registerWav();
    registerAiff();
    registerMp4();
    registerFlacFormat();
    registerMatroska();
    registerMp3();
  });

  tearDown(clearFormats);

  group('注册顺序', () {
    test('注册顺序即嗅探顺序', () {
      expect(allFormats().map((f) => f.name).toList(), <String>[
        'WAV',
        'AIFF',
        'MP4',
        'FLAC',
        'Matroska',
        'MP3',
      ]);
    });

    test('每个已注册格式都有素材可以认', () {
      // 防止用例表漏掉新注册的格式。
      final registered = allFormats().map((f) => f.name).toSet();
      final covered = _cases.map((c) => c.format).toSet();
      expect(covered, containsAll(registered));
    });

    test('先注册的命中者胜出', () {
      // 替身先注册 → 它赢。
      clearFormats();
      registerFormat(_alwaysMatches('AlwaysMatches'));
      registerWav();
      expect(
        _detectName(_fixture('wav_pcm_s16le_44100_stereo.normal.wav')),
        'AlwaysMatches',
      );

      // 替身后注册 → 先命中的真格式赢。
      clearFormats();
      registerWav();
      registerFormat(_alwaysMatches('AlwaysMatches'));
      expect(
        _detectName(_fixture('wav_pcm_s16le_44100_stereo.normal.wav')),
        'WAV',
      );
    });
  });

  group('每个素材只被自己的 detect 命中', () {
    for (final c in _cases) {
      test('${c.fixture} -> ${c.format}', () {
        expect(_detectName(_fixture(c.fixture)), c.format);
      });
    }

    for (final c in _cases) {
      test('${c.fixture}：别的格式的 detect 不抢', () {
        final claimants = <String>[];
        for (final spec in allFormats()) {
          if (_claims(spec, _fixture(c.fixture))) claimants.add(spec.name);
        }
        expect(claimants, <String>[c.format]);
      });
    }

    test('没有任何两个格式能同时认同一个素材（顺序无关）', () {
      for (final c in _cases) {
        final claimants = allFormats()
            .where((spec) => _claims(spec, _fixture(c.fixture)))
            .map((spec) => spec.name)
            .toList();
        expect(claimants, hasLength(1), reason: '${c.fixture} 被多个格式认领');
      }
    });
  });

  group('MP4 与 MOV / Matroska 与 WebM', () {
    test('MOV 不单独注册，归到 MP4', () {
      final names = allFormats().map((f) => f.name).toList();
      expect(names, isNot(contains('MOV')));
      expect(names, isNot(contains('QuickTime')));
      expect(_detectName(_fixture('mov_mpeg4_aac_320x240.normal.mov')), 'MP4');
      expect(
        _detectName(_fixture('mov_mpeg4_aac_320x240.normal.truncated.mov')),
        'MP4',
      );
    });

    test('WebM 不单独注册，归到 Matroska', () {
      final names = allFormats().map((f) => f.name).toList();
      expect(names, isNot(contains('WebM')));
      expect(
        _detectName(_fixture('webm_vp8_vorbis_320x240.normal.webm')),
        'Matroska',
      );
      expect(
        _detectName(_fixture('webm_vp8_vorbis_320x240.normal.truncated.webm')),
        'Matroska',
      );
    });

    test('MP4 与 MOV 用 ftyp 的 brand 区分', () {
      expect(
        _semanticValue('mp4_h264_aac_320x240.normal.mp4', 'brand'),
        'isom',
      );
      expect(
        _semanticValue('mov_mpeg4_aac_320x240.normal.mov', 'brand'),
        'qt  ',
      );
    });

    test('Matroska 与 WebM 用 container_format 区分', () {
      // container_format 的值是**原始 DocType**（'matroska' / 'webm'）——
      // 文件里写的就是它，导出 JSON 时要保真。
      expect(
        _semanticValue('mkv_vp9_opus_320x240.normal.mkv', 'container_format'),
        'matroska',
      );
      expect(
        _semanticValue(
          'webm_vp8_vorbis_320x240.normal.webm',
          'container_format',
        ),
        'webm',
      );
    });
  });

  group('扩展名只是提示，内容说了算', () {
    test('扩展名不符：.wav 的文件其实是 MP4', () {
      final dir = Directory.systemTemp.createTempSync('media_info_detect');
      addTearDown(() => dir.deleteSync(recursive: true));

      final mislabelled = File('${dir.path}/mislabelled.wav')
        ..writeAsBytesSync(
          File(_fixture('mp4_h264_aac_320x240.normal.mp4')).readAsBytesSync(),
        );

      expect(_detectName(mislabelled.path), 'MP4');
      // 扩展名确实与检测结果对不上——这正是票 20 要提示用户的场景。
      expect(mislabelled.path.endsWith('.wav'), isTrue);
    });

    test('无扩展名：照样认得出，且不构成"扩展名不符"', () {
      final dir = Directory.systemTemp.createTempSync('media_info_detect');
      addTearDown(() => dir.deleteSync(recursive: true));

      final noExtension = File('${dir.path}/noextension')
        ..writeAsBytesSync(
          File(_fixture('mp4_h264_aac_320x240.normal.mp4')).readAsBytesSync(),
        );

      expect(_detectName(noExtension.path), 'MP4');
      // 没有扩展名可比对 → 不存在"扩展名不符"这回事。
      final name = noExtension.path.split(Platform.pathSeparator).last;
      expect(name.contains('.'), isFalse);
    });

    test('不是媒体文件：返回 null', () {
      final dir = Directory.systemTemp.createTempSync('media_info_detect');
      addTearDown(() => dir.deleteSync(recursive: true));

      final text = File('${dir.path}/notes.txt')
        ..writeAsStringSync('这不是媒体文件，只是一段纯文本。\n');
      expect(_detectName(text.path), isNull);

      // 扩展名像媒体，内容不是 → 一样认不出来。
      final fake = File('${dir.path}/fake.wav')
        ..writeAsStringSync('这不是媒体文件，只是一段纯文本。\n');
      expect(_detectName(fake.path), isNull);
    });

    test('常见的非媒体文件不会被误认', () {
      const List<({String name, List<int> bytes})> others = [
        (name: 'photo.jpg', bytes: [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]),
        (name: 'pic.png', bytes: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]),
        (name: 'doc.pdf', bytes: [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31]),
        (name: 'archive.zip', bytes: [0x50, 0x4B, 0x03, 0x04, 0x00, 0x00]),
        (name: 'empty', bytes: []),
      ];
      for (final other in others) {
        expect(
          _detectName(_writeTempFile(other.name, other.bytes)),
          isNull,
          reason: '${other.name} 不该被认成媒体文件',
        );
      }
    });

    test('RIFF 但不是 WAVE（AVI）：不认成 WAV，也没人抢', () {
      // WAV 的 detect 认的是偏移 8 的 `WAVE`，不是光看 `RIFF`。
      const List<int> riffAvi = [
        0x52, 0x49, 0x46, 0x46, 0x20, 0x00, 0x00, 0x00, //
        0x41, 0x56, 0x49, 0x20,
      ];
      expect(_detectName(_writeTempFile('clip.avi', riffAvi)), isNull);
    });

    test('没有 ID3 标签的裸 MP3 帧：仍然认成 MP3', () {
      // MP3 的 detect 除了 `ID3`，还回退到 MPEG 帧头同步字。
      const List<int> rawFrame = [
        0xFF, 0xFB, 0x90, 0x64, 0x00, 0x00, 0x00, 0x00, //
      ];
      expect(_detectName(_writeTempFile('raw.mp3', rawFrame)), 'MP3');
    });
  });

  group('没有 ftyp 块的 ISO base media 也能认出来', () {
    test('老式 QuickTime（首块是 moov）', () {
      // 传统 QuickTime 的第一个 box 是 moov / mdat，没有 ftyp。
      // 修复后 _detectIsoBmff 会走顶层 box 链，而不是死盯偏移 4。
      const List<int> legacyMov = [
        0x00, 0x00, 0x00, 0x14, 0x6D, 0x6F, 0x6F, 0x76, //
        0x00, 0x00, 0x00, 0x00,
      ];
      expect(_detectName(_writeTempFile('legacy.mov', legacyMov)), 'MP4');
    });

    test('分片 MP4（首块是 styp / moof）', () {
      const List<int> fragmented = [
        0x00, 0x00, 0x00, 0x10, 0x73, 0x74, 0x79, 0x70, //
        0x00, 0x00, 0x00, 0x00,
      ];
      expect(_detectName(_writeTempFile('fragmented.mp4', fragmented)), 'MP4');
    });

    test('QuickTime 的 wide 填充块', () {
      const List<int> wideFirst = [
        0x00, 0x00, 0x00, 0x10, 0x77, 0x69, 0x64, 0x65, //
        0x00, 0x00, 0x00, 0x00,
      ];
      expect(_detectName(_writeTempFile('wide.mov', wideFirst)), 'MP4');
    });

    test('长度字段不合理的假 ftyp 不被认成 MP4', () {
      // "XXXXftyp" —— 偏移 4 确实是 ftyp，但前面的长度字段荒谬。
      const List<int> bogus = [
        0xFF, 0xFF, 0xFF, 0xFF, 0x66, 0x74, 0x79, 0x70, //
        0x00, 0x00, 0x00, 0x00,
      ];
      expect(_detectName(_writeTempFile('bogus.mp4', bogus)), isNull);
    });
  });

  group('detect 只读文件头', () {
    test('每个 detect 读的都是头几个字节', () {
      for (final spec in allFormats()) {
        final detect = spec.detect;
        expect(detect, isNotNull, reason: '${spec.name} 没有 detect');
        final detectFn = detect!;
        for (final c in _cases.where((c) => c.format == spec.name)) {
          final counter = _CountingByteSource(
            FileByteSource.fromPath(_fixture(c.fixture)),
          );
          addTearDown(counter.close);
          detectFn(counter);
          expect(
            counter.bytesRead,
            lessThanOrEqualTo(16),
            reason: '${spec.name} 读了 ${counter.bytesRead} 字节（${c.fixture}）',
          );
          expect(
            counter.maxEnd,
            lessThanOrEqualTo(16),
            reason: '${spec.name} 读到了偏移 ${counter.maxEnd}（${c.fixture}）',
          );
        }
      }
    });
  });
}
