import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/core/engine.dart';
import 'package:media_info/src/core/node.dart';
import 'package:media_info/src/core/registry.dart';
import 'package:media_info/src/formats/riff.dart';

import '../core/support/memory_byte_source.dart';

/// 读一个素材文件。
MemoryByteSource _fixture(String name) =>
    MemoryByteSource.of(File('test/fixtures/$name').readAsBytesSync());

/// 收集结构树里出现过的全部块类型。
Set<String> _chunkTypes(ContainerNode node) {
  final types = <String>{node.type};
  for (final child in node.children) {
    types.addAll(_chunkTypes(child));
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

/// 节点的字段值表。
Map<String, Object?> _values(ContainerNode node) => <String, Object?>{
  for (final field in node.fields) field.key: field.value,
};

/// 提取器产出的字段值表。
Map<String, Object?> _semantic(List<SemanticField> fields) => <String, Object?>{
  for (final field in fields) field.key: field.value,
};

void main() {
  group('WAV（RIFF）', () {
    test('正常样本：结构树与统一语义字段', () {
      final result = parseWav(
        _fixture('wav_pcm_s16le_44100_stereo.normal.wav'),
      );

      expect(result.truncated, isFalse);
      expect(result.error, isNull);

      // 块覆盖率清单。
      final types = _chunkTypes(result.root);
      expect(types, containsAll(<String>['RIFF', 'fmt ', 'data']));

      final riff = _find(result.root, 'RIFF')!;
      expect(riff.offset, 0);
      expect(riff.size, 44178);
      expect(riff.dataOffset, 8);
      expect(riff.dataSize, 44170);

      final fmt = _find(result.root, 'fmt ')!;
      expect(fmt.offset, 12);
      expect(fmt.size, 24);
      expect(fmt.dataOffset, 20);
      expect(fmt.dataSize, 16);
      expect(_values(fmt), <String, Object?>{
        'wFormatTag': 1,
        'channels': 2,
        'sample_rate': 44100,
        'byte_rate': 176400,
        'block_align': 4,
        'bit_depth': 16,
      });

      final data = _find(result.root, 'data')!;
      expect(data.offset, 70);
      expect(data.size, 44108);
      expect(data.dataOffset, 78);
      expect(data.dataSize, 44100);

      // LIST 是容器型块，载荷开头是 list type `INFO`。
      final list = _find(result.root, 'LIST')!;
      expect(list.offset, 36);
      expect(list.dataOffset, 44);
      expect(_values(list)['list_type'], 'INFO');
      expect(_find(result.root, 'ISFT')!.offset, 48);

      final fields = extractWavFields(result.root);
      expect(_semantic(fields), <String, Object?>{
        'sample_rate': 44100,
        'bit_depth': 16,
        'channels': 2,
        'codec': 1,
        'duration': 0.25,
        'overall_bitrate': 1413696,
      });

      final byKey = <String, SemanticField>{
        for (final field in fields) field.key: field,
      };
      expect(byKey['sample_rate']!.label, '采样率');
      expect(byKey['sample_rate']!.unit, 'Hz');
      expect(byKey['bit_depth']!.label, '位深');
      expect(byKey['bit_depth']!.unit, 'bit');
      expect(byKey['channels']!.label, '声道数');
      expect(byKey['codec']!.label, '编码标识');
      expect(byKey['duration']!.label, '时长');
      expect(byKey['duration']!.unit, 's');
      expect(byKey['overall_bitrate']!.label, '平均码率');
      expect(byKey['overall_bitrate']!.unit, 'bit/s');
      expect(byKey['overall_bitrate']!.origin, FieldOrigin.derived);
      expect(byKey['sample_rate']!.source, 'fmt ');
    });

    test('边界样本：8bit 单声道 8000Hz', () {
      final result = parseWav(_fixture('wav_pcm_u8_8000_mono.edge.wav'));

      expect(result.truncated, isFalse);
      expect(result.error, isNull);

      final fmt = _find(result.root, 'fmt ')!;
      expect(_values(fmt)['sample_rate'], 8000);
      expect(_values(fmt)['channels'], 1);
      expect(_values(fmt)['bit_depth'], 8);

      final fields = _semantic(extractWavFields(result.root));
      expect(fields['sample_rate'], 8000);
      expect(fields['channels'], 1);
      expect(fields['bit_depth'], 8);
      expect(fields['duration'], 0.25);
    });

    test('边界样本：WAVEFORMATEXTENSIBLE（fmt 载荷是 tagged union）', () {
      final result = parseWav(_fixture('wav_pcm_s24le_48000_stereo.edge.wav'));

      expect(result.truncated, isFalse);
      expect(result.error, isNull);

      final fmt = _find(result.root, 'fmt ')!;
      expect(fmt.dataSize, 40);
      final values = _values(fmt);
      expect(values['wFormatTag'], 65534);
      expect(values['sample_rate'], 48000);
      expect(values['channels'], 2);
      expect(values['bit_depth'], 24);
      expect(values['cbSize'], 22);

      // 扩展内容由手写逃生口解码。
      final extension = values['extension']! as Uint8List;
      expect(extension.length, 22);
      final decoded = decodeWaveFormatExExtension(extension);
      expect(decoded.validBits, 24);
      expect(decoded.channelMask, 3);
      expect(decoded.subFormat.sublist(0, 4), <int>[1, 0, 0, 0]);

      final fields = _semantic(extractWavFields(result.root));
      expect(fields['sample_rate'], 48000);
      expect(fields['bit_depth'], 24);
      expect(fields['channels'], 2);
      expect(fields['codec'], 65534);
    });

    test('截断样本：降级并给出中文错误说明，已解析的部分照常返回', () {
      final result = parseWav(
        _fixture('wav_pcm_s16le_44100_stereo.normal.truncated.wav'),
      );

      expect(result.truncated, isTrue);
      expect(result.error, isNotNull);
      expect(result.error, contains('截断'));
      // 错误说明里的偏移量是原文件的坐标。
      expect(result.error, contains('26506'));

      // 已读到的结构还在。
      final types = _chunkTypes(result.root);
      expect(types, containsAll(<String>['RIFF', 'fmt ', 'data']));

      final riff = _find(result.root, 'RIFF')!;
      expect(riff.isOpaque, isTrue);
      expect(riff.dataSize, lessThan(44170));
    });

    test('长度撒谎样本：不越界、不崩，报截断并保留能读到的结构', () {
      final source = _fixture('wav_pcm_s16le_44100_stereo.normal.liesize.wav');
      final result = parseWav(source);

      expect(result.truncated, isTrue);
      expect(result.error, isNotNull);

      // 结构没有越界：每个节点的偏移 + 长度都在文件范围内。
      void check(ContainerNode node) {
        expect(node.offset + node.size, lessThanOrEqualTo(source.length));
        for (final child in node.children) {
          check(child);
        }
      }

      check(result.root);

      final types = _chunkTypes(result.root);
      expect(types, containsAll(<String>['RIFF', 'fmt ']));
    });
  });

  group('AIFF（FORM）', () {
    test('正常样本：结构树与统一语义字段', () {
      final result = parseAiff(
        _fixture('aiff_pcm_s16be_48000_mono.normal.aiff'),
      );

      expect(result.truncated, isFalse);
      expect(result.error, isNull);

      final types = _chunkTypes(result.root);
      expect(types, containsAll(<String>['FORM', 'COMM', 'SSND']));

      final form = _find(result.root, 'FORM')!;
      expect(form.offset, 0);
      expect(form.size, 24054);
      expect(form.dataOffset, 8);
      expect(_values(form)['form_type'], 'AIFF');

      final comm = _find(result.root, 'COMM')!;
      expect(comm.offset, 12);
      expect(comm.size, 26);
      expect(comm.dataOffset, 20);
      expect(comm.dataSize, 18);
      final values = _values(comm);
      expect(values['num_channels'], 1);
      expect(values['num_sample_frames'], 12000);
      expect(values['sample_size'], 16);

      final ssnd = _find(result.root, 'SSND')!;
      expect(ssnd.offset, 38);
      expect(ssnd.dataOffset, 46);
      expect(_values(ssnd)['offset'], 0);

      final fields = extractAiffFields(result.root);
      expect(_semantic(fields), <String, Object?>{
        'sample_rate': 48000,
        'bit_depth': 16,
        'channels': 1,
        'codec': 'NONE',
        'duration': 0.25,
        'overall_bitrate': 769728,
      });
      final byKey = <String, SemanticField>{
        for (final field in fields) field.key: field,
      };
      expect(byKey['sample_rate']!.label, '采样率');
      expect(byKey['sample_rate']!.unit, 'Hz');
      expect(byKey['sample_rate']!.source, 'COMM');
      expect(byKey['overall_bitrate']!.origin, FieldOrigin.derived);
    });

    test('边界样本：24bit 立体声 44100Hz', () {
      final result = parseAiff(
        _fixture('aiff_pcm_s24be_44100_stereo.edge.aiff'),
      );

      expect(result.truncated, isFalse);
      expect(result.error, isNull);

      final values = _values(_find(result.root, 'COMM')!);
      expect(values['num_channels'], 2);
      expect(values['num_sample_frames'], 11025);
      expect(values['sample_size'], 24);

      final fields = _semantic(extractAiffFields(result.root));
      expect(fields['sample_rate'], 44100);
      expect(fields['bit_depth'], 24);
      expect(fields['channels'], 2);
      expect(fields['duration'], 0.25);
    });
  });

  group('手写逃生口', () {
    test('80 位扩展精度浮点解码', () {
      // 48000 = 0x400E BB80 0000 0000 0000
      expect(
        decodeExtended80(
          Uint8List.fromList(<int>[0x40, 0x0E, 0xBB, 0x80, 0, 0, 0, 0, 0, 0]),
        ),
        48000,
      );
      // 44100 = 0x400E AC44 0000 0000 0000
      expect(
        decodeExtended80(
          Uint8List.fromList(<int>[0x40, 0x0E, 0xAC, 0x44, 0, 0, 0, 0, 0, 0]),
        ),
        44100,
      );
      // 0
      expect(decodeExtended80(Uint8List.fromList(List<int>.filled(10, 0))), 0);
      // 负数：-48000
      expect(
        decodeExtended80(
          Uint8List.fromList(<int>[0xC0, 0x0E, 0xBB, 0x80, 0, 0, 0, 0, 0, 0]),
        ),
        -48000,
      );
      // 字节不够 → 0，不抛异常。
      expect(decodeExtended80(Uint8List.fromList(<int>[1, 2, 3])), 0);
    });

    test('WAVEFORMATEXTENSIBLE 扩展解码', () {
      final bytes = Uint8List.fromList(<int>[
        0x18, 0x00, // validBits = 24
        0x03, 0x00, 0x00, 0x00, // channelMask = 3
        0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x00, //
        0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71,
      ]);
      final decoded = decodeWaveFormatExExtension(bytes);
      expect(decoded.validBits, 24);
      expect(decoded.channelMask, 3);
      expect(decoded.subFormat.length, 16);
      expect(decoded.subFormat[0], 1);

      // 长度不够 → 空结果，不抛异常。
      final short = decodeWaveFormatExExtension(
        Uint8List.fromList(<int>[1, 2, 3]),
      );
      expect(short.validBits, 0);
      expect(short.subFormat, isEmpty);
    });
  });

  group('嗅探与注册', () {
    test('detect 只看文件头', () {
      expect(
        detectWav(_fixture('wav_pcm_s16le_44100_stereo.normal.wav')),
        isTrue,
      );
      expect(
        detectAiff(_fixture('aiff_pcm_s16be_48000_mono.normal.aiff')),
        isTrue,
      );
      expect(
        detectWav(_fixture('aiff_pcm_s16be_48000_mono.normal.aiff')),
        isFalse,
      );
      expect(
        detectAiff(_fixture('wav_pcm_s16le_44100_stereo.normal.wav')),
        isFalse,
      );
    });

    test('注册后 detectFormat 认得本格式', () {
      clearFormats();
      registerWav();
      registerAiff();

      expect(
        detectFormat(_fixture('wav_pcm_s16le_44100_stereo.normal.wav'))?.name,
        'WAV',
      );
      expect(
        detectFormat(_fixture('aiff_pcm_s16be_48000_mono.normal.aiff'))?.name,
        'AIFF',
      );
      expect(
        allFormats().map((format) => format.name),
        containsAll(<String>['WAV', 'AIFF']),
      );
    });

    test('扩展名不符也能识别（只看内容）', () {
      clearFormats();
      registerWav();
      registerAiff();

      final dir = Directory.systemTemp.createTempSync('media_info_riff');
      addTearDown(() => dir.deleteSync(recursive: true));
      final mislabelled = File('${dir.path}/mislabelled.bin')
        ..writeAsBytesSync(
          File(
            'test/fixtures/wav_pcm_s16le_44100_stereo.normal.wav',
          ).readAsBytesSync(),
        );

      final source = MemoryByteSource.of(mislabelled.readAsBytesSync());
      expect(detectFormat(source)?.name, 'WAV');
    });
  });

  group('核心引擎的顶层规格表', () {
    test('parseContainer 能读出顶层 RIFF 块（form type 是块的一个字段）', () {
      final result = parseContainer(
        wavSpec,
        _fixture('wav_pcm_s16le_44100_stereo.normal.wav'),
      );

      expect(result.truncated, isFalse);
      expect(result.error, isNull);
      expect(result.root.type, 'WAV');
      expect(result.root.children, hasLength(1));
      final riff = result.root.children.single;
      expect(riff.type, 'RIFF');
      expect(riff.offset, 0);
      expect(riff.size, 44178);
      expect(_values(riff)['form_type'], 'WAVE');
    });
  });
}
