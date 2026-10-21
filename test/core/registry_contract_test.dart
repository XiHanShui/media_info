/// 格式注册表的契约测试。
///
/// 契约见 `docs/design/core-api.md` §6：
/// - 注册表登记的是**规格表 + 可选的叶子提取器**，不是解析器对象；
/// - **按内容嗅探**选出格式，识别不出返回 `null`；
/// - 嗅探按注册顺序进行，第一个命中者胜出。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/core/byte_source.dart';
import 'package:media_info/src/core/engine.dart';
import 'package:media_info/src/core/node.dart';
import 'package:media_info/src/core/registry.dart';
import 'package:media_info/src/core/spec.dart';
import 'package:media_info/src/formats/all_formats.dart';

import '../support/fixture_paths.dart';
import 'support/memory_byte_source.dart';

ContainerSpec _emptySpec(String name) =>
    ContainerSpec(name: name, header: const HeaderRule(), children: const {});

void main() {
  group('注册表的基本动作', () {
    setUp(clearFormats);
    tearDown(clearFormats);

    test('注册表初始为空，识别不出任何格式', () {
      expect(allFormats(), isEmpty);
      expect(detectFormat(MemoryByteSource.of(<int>[1, 2, 3])), isNull);
    });

    test('注册顺序即嗅探顺序：两个都能匹配时先注册的那个胜出', () {
      registerFormat(
        FormatSpec(
          name: 'AAA',
          container: _emptySpec('AAA'),
          detect: (ByteSource source) => source.read(0, 4).first == 0xAA,
        ),
      );
      registerFormat(
        FormatSpec(
          name: 'BBB',
          container: _emptySpec('BBB'),
          detect: (ByteSource source) => source.read(0, 4).first == 0xAA,
        ),
      );

      expect(allFormats().map((FormatSpec f) => f.name), <String>[
        'AAA',
        'BBB',
      ]);
      expect(
        detectFormat(MemoryByteSource.of(<int>[0xAA, 0, 0, 0]))?.name,
        'AAA',
      );
    });

    test('同名格式被替换而不是重复登记，且保持原来的位置', () {
      registerFormat(FormatSpec(name: 'AAA', container: _emptySpec('AAA')));
      registerFormat(FormatSpec(name: 'BBB', container: _emptySpec('BBB')));
      registerFormat(FormatSpec(name: 'AAA', container: _emptySpec('AAA2')));

      expect(allFormats().map((FormatSpec f) => f.name), <String>[
        'AAA',
        'BBB',
      ]);
      expect(allFormats().first.container.name, 'AAA2');
    });

    test('allFormats 返回的列表不可修改', () {
      registerFormat(FormatSpec(name: 'AAA', container: _emptySpec('AAA')));

      expect(
        () => allFormats().add(
          FormatSpec(name: 'BBB', container: _emptySpec('BBB')),
        ),
        throwsUnsupportedError,
      );
    });

    test('clearFormats 清空注册表', () {
      registerFormat(FormatSpec(name: 'AAA', container: _emptySpec('AAA')));
      expect(allFormats(), hasLength(1));

      clearFormats();

      expect(allFormats(), isEmpty);
    });

    test('注册表登记的是规格表本身（同一个实例）', () {
      final ContainerSpec spec = _emptySpec('WAV');
      registerFormat(FormatSpec(name: 'WAV', container: spec));

      final FormatSpec format = allFormats().single;
      expect(format.container, same(spec));
      expect(format.extractor, isNull);
      expect(format.detect, isNull);
      expect(format.parser, isNull);
    });

    test('文件短到读不出魔数时不算命中，也不崩溃', () {
      registerFormat(
        FormatSpec(
          name: 'AAA',
          container: _emptySpec('AAA'),
          detect: (ByteSource source) => source.read(0, 4).first == 0xAA,
        ),
      );

      expect(detectFormat(MemoryByteSource.of(<int>[0xAA])), isNull);
    });

    test('detect 抛 TruncatedFile 时跳过该格式，继续试后面的', () {
      registerFormat(
        FormatSpec(
          name: 'Short',
          container: _emptySpec('Short'),
          detect: (ByteSource source) => source.read(0, 8).first == 0xAA,
        ),
      );
      registerFormat(
        FormatSpec(
          name: 'Long',
          container: _emptySpec('Long'),
          detect: (ByteSource source) => source.read(0, 4).first == 0xAA,
        ),
      );

      expect(
        detectFormat(MemoryByteSource.of(<int>[0xAA, 0, 0, 0]))?.name,
        'Long',
      );
    });
  });

  group('parseFormat：调用方的唯一入口', () {
    setUp(clearFormats);
    tearDown(clearFormats);

    test('格式自带 parser 时用 parser，depth 原样透传', () {
      final List<int> depths = <int>[];
      final FormatSpec spec = FormatSpec(
        name: 'Custom',
        container: _emptySpec('Custom'),
        parser: (ByteSource source, {int depth = 1}) {
          depths.add(depth);
          return ParseResult(
            root: ContainerNode(
              type: 'Custom',
              offset: 0,
              size: source.length,
              dataOffset: 0,
              dataSize: source.length,
            ),
          );
        },
      );

      final ParseResult result = parseFormat(
        spec,
        MemoryByteSource.of(<int>[0, 0, 0, 0]),
        depth: 7,
      );

      expect(depths, <int>[7]);
      expect(result.root.type, 'Custom');
    });

    test('没有 parser 时退回规格表', () {
      final FormatSpec spec = FormatSpec(
        name: 'Plain',
        container: _emptySpec('Plain'),
      );

      final ParseResult result = parseFormat(
        spec,
        MemoryByteSource.of(<int>[0, 0, 0, 0]),
        depth: 2,
      );

      expect(result.root.type, 'Plain');
      expect(result.root.size, 4);
    });

    test('parser 抛出的异常不被吞掉（调用方能感知失败）', () {
      final FormatSpec spec = FormatSpec(
        name: 'Boom',
        container: _emptySpec('Boom'),
        parser: (ByteSource source, {int depth = 1}) =>
            throw StateError('boom'),
      );

      expect(
        () => parseFormat(spec, MemoryByteSource.of(<int>[0])),
        throwsStateError,
      );
    });
  });

  group('全部已注册格式', () {
    test('注册顺序：结构明确的容器格式排在宽松的 MP3 前面', () {
      registerAllFormats();

      expect(allFormats().map((FormatSpec f) => f.name), <String>[
        'WAV',
        'AIFF',
        'MP4',
        'FLAC',
        'Matroska',
        'MP3',
      ]);
    });

    test('重复注册是安全的（同名格式被替换，顺序不变）', () {
      registerAllFormats();
      registerAllFormats();

      expect(allFormats().map((FormatSpec f) => f.name), <String>[
        'WAV',
        'AIFF',
        'MP4',
        'FLAC',
        'Matroska',
        'MP3',
      ]);
    });

    test('每个已注册格式都带嗅探函数与叶子提取器', () {
      registerAllFormats();

      for (final FormatSpec format in allFormats()) {
        expect(format.detect, isNotNull, reason: '${format.name} 缺嗅探函数');
        expect(format.extractor, isNotNull, reason: '${format.name} 缺叶子提取器');
      }
    });

    test('按内容嗅探：每个素材都被认成正确的格式', () {
      registerAllFormats();

      const Map<String, String> expected = <String, String>{
        'wav_pcm_s16le_44100_stereo.normal.wav': 'WAV',
        'aiff_pcm_s16be_48000_mono.normal.aiff': 'AIFF',
        'flac_s16_44100_stereo.normal.flac': 'FLAC',
        'mp3_cbr128_44100_stereo.normal.mp3': 'MP3',
        'mp4_h264_aac_320x240.normal.mp4': 'MP4',
        'mov_mpeg4_aac_320x240.normal.mov': 'MP4',
        'mkv_vp9_opus_320x240.normal.mkv': 'Matroska',
        'webm_vp8_vorbis_320x240.normal.webm': 'Matroska',
      };

      for (final MapEntry<String, String> entry in expected.entries) {
        final FileByteSource source = fixtureSource(entry.key);
        addTearDown(source.close);

        expect(
          detectFormat(source)?.name,
          entry.value,
          reason: '${entry.key} 应该被认成 ${entry.value}',
        );
      }
    });

    test('非媒体文件识别不出来，返回 null', () {
      registerAllFormats();

      expect(
        detectFormat(
          MemoryByteSource.of(
            List<int>.generate(64, (int index) => (index * 7) & 0xFF),
          ),
        ),
        isNull,
      );
    });

    test('空文件识别不出来', () {
      registerAllFormats();

      expect(detectFormat(MemoryByteSource.of(const <int>[])), isNull);
    });
  });
}
