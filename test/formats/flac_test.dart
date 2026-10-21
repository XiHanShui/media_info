import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/core/byte_source.dart';
import 'package:media_info/src/core/node.dart';
import 'package:media_info/src/core/registry.dart';
import 'package:media_info/src/core/spec.dart';
import 'package:media_info/src/formats/flac.dart';

import '../core/support/memory_byte_source.dart';

/// 打开样本文件（测试结束时关闭句柄）。
FileByteSource _fixture(String name) {
  final source = FileByteSource.fromPath('test/fixtures/$name');
  addTearDown(source.close);
  return source;
}

/// 按 key 找语义字段。
SemanticField? _byKey(List<SemanticField> fields, String key) {
  for (final field in fields) {
    if (field.key == key) return field;
  }
  return null;
}

/// 递归收集结构树里的所有节点。
List<ContainerNode> _walk(ContainerNode node) {
  final out = <ContainerNode>[node];
  for (final child in node.children) {
    out.addAll(_walk(child));
  }
  return out;
}

/// 按 MSB 优先把「值 + 位宽」打包成字节（FLAC 的位域是大端位序）。
List<int> _packBits(List<(int value, int width)> fields) {
  final bits = <int>[];
  for (final (value, width) in fields) {
    for (var i = width - 1; i >= 0; i--) {
      bits.add((value >> i) & 1);
    }
  }
  final bytes = <int>[];
  for (var i = 0; i < bits.length; i += 8) {
    var byte = 0;
    for (var j = 0; j < 8 && i + j < bits.length; j++) {
      byte = (byte << 1) | bits[i + j];
    }
    bytes.add(byte);
  }
  return bytes;
}

/// 造一个只有一个元数据块的最小 FLAC 文件。
List<int> _flacFile(List<int> header, List<int> payload) => <int>[
  ...'fLaC'.codeUnits,
  ...header,
  ...payload,
];

void main() {
  group('FLAC 结构树', () {
    test('根节点是整个文件，子节点是元数据块', () {
      final result = parseFlac(_fixture('flac_s16_44100_stereo.normal.flac'));

      expect(result.truncated, isFalse);
      expect(result.error, isNull);
      expect(result.root.type, 'FLAC');
      expect(result.root.offset, 0);
      expect(result.root.size, 11450);

      expect(result.root.children.map((c) => c.type), [
        'STREAMINFO',
        'VORBIS_COMMENT',
        'PADDING',
      ]);
    });

    test('每个元数据块的偏移与长度都对得上文件', () {
      final result = parseFlac(_fixture('flac_s16_44100_stereo.normal.flac'));

      final streamInfo = result.root.children[0];
      expect(streamInfo.offset, 4);
      expect(streamInfo.size, 38); // 4 字节块头 + 34 字节载荷
      expect(streamInfo.dataOffset, 8);
      expect(streamInfo.dataSize, 34);
      expect(streamInfo.isOpaque, isFalse);

      final comment = result.root.children[1];
      expect(comment.offset, 42);
      expect(comment.size, 48);
      expect(comment.dataOffset, 46);
      expect(comment.dataSize, 44);

      final padding = result.root.children[2];
      expect(padding.offset, 90);
      expect(padding.size, 8196);
      expect(padding.isOpaque, isTrue);
    });

    test('块覆盖率清单：STREAMINFO 与 VORBIS_COMMENT 都在树里', () {
      final result = parseFlac(_fixture('flac_s16_44100_stereo.normal.flac'));

      final types = _walk(result.root).map((n) => n.type).toSet();
      expect(types, containsAll(<String>['STREAMINFO', 'VORBIS_COMMENT']));
    });
  });

  group('FLAC STREAMINFO 位域', () {
    test('按位域解出采样率、声道数、位深与总采样数', () {
      final result = parseFlac(_fixture('flac_s16_44100_stereo.normal.flac'));

      final streamInfo = result.root.children.first;
      final values = <String, Object?>{
        for (final field in streamInfo.fields) field.key: field.value,
      };

      expect(values['min_block_size'], 4608);
      expect(values['max_block_size'], 4608);
      expect(values['min_frame_size'], 588);
      expect(values['max_frame_size'], 1288);
      expect(values['sample_rate'], 44100);
      expect(values['channels'], 2);
      expect(values['bits_per_sample'], 16);
      expect(values['total_samples'], 11025);
      expect(values['md5'], 'f71656b039680036049eae0992606cfe');
    });

    test('24bit / 96kHz 样本解出同样的位域', () {
      final result = parseFlac(_fixture('flac_s24_96000_mono.edge.flac'));

      final streamInfo = result.root.children.first;
      final values = <String, Object?>{
        for (final field in streamInfo.fields) field.key: field.value,
      };

      expect(values['min_block_size'], 8192);
      expect(values['max_block_size'], 8192);
      expect(values['min_frame_size'], 7032);
      expect(values['max_frame_size'], 8276);
      expect(values['sample_rate'], 96000);
      expect(values['channels'], 1);
      expect(values['bits_per_sample'], 24);
      expect(values['total_samples'], 24000);
      expect(values['md5'], 'cfa8189896c72e6578c30f0348e90bdf');
    });

    test('手造的 STREAMINFO 位域按大端位序解出', () {
      // 规范里的声道数与每样本位数存的是「真实值减一」。
      final payload = <int>[
        ..._packBits([(4096, 16)]), // min block size
        ..._packBits([(4096, 16)]), // max block size
        ..._packBits([(0, 24)]), // min frame size
        ..._packBits([(0, 24)]), // max frame size
        ..._packBits([
          (48000, 20), // sample rate
          (1, 3), // channels - 1 → 2 声道
          (23, 5), // bits per sample - 1 → 24 bit
          (96000, 36), // total samples
        ]),
        ...List<int>.filled(16, 0xAB), // md5
      ];
      // 0x80 = last-metadata-block + 类型 0（STREAMINFO），长度 34 字节。
      final file = _flacFile(<int>[0x80, 0x00, 0x00, 0x22], payload);

      final result = parseFlac(MemoryByteSource.of(file));

      final streamInfo = result.root.children.single;
      final values = <String, Object?>{
        for (final field in streamInfo.fields) field.key: field.value,
      };
      expect(values['sample_rate'], 48000);
      expect(values['channels'], 2);
      expect(values['bits_per_sample'], 24);
      expect(values['total_samples'], 96000);
      expect(values['md5'], 'abababababababababababababababab');
    });
  });

  group('FLAC 异常输入', () {
    test('未知的元数据块类型降级成不透明叶子', () {
      // 类型码 11 是保留类型，表里没有 → 不透明叶子，不丢。
      final file = _flacFile(<int>[0x8B, 0x00, 0x00, 0x02], <int>[0xAA, 0xBB]);

      final result = parseFlac(MemoryByteSource.of(file));

      expect(result.truncated, isFalse);
      final unknown = result.root.children.single;
      expect(unknown.type, 'UNKNOWN');
      expect(unknown.isOpaque, isTrue);
      expect(unknown.offset, 4);
      expect(unknown.size, 6);
    });

    test('不是 FLAC 的文件给出中文错误说明，不抛异常', () {
      final result = parseFlac(
        MemoryByteSource.of(<int>[0x52, 0x49, 0x46, 0x46, 0x00, 0x00]),
      );

      expect(result.error, isNotNull);
      expect(result.root.children, isEmpty);
    });

    test('太短的文件报截断', () {
      final result = parseFlac(MemoryByteSource.of(<int>[0x66, 0x4C]));

      expect(result.truncated, isTrue);
      expect(result.error, isNotNull);
    });
  });

  group('FLAC VORBIS_COMMENT', () {
    test('长度字段按小端读', () {
      final result = parseFlac(_fixture('flac_s16_44100_stereo.normal.flac'));

      final comment = result.root.children[1];
      final values = <String, Object?>{
        for (final field in comment.fields) field.key: field.value,
      };

      expect(values['vendor_length'], 12);
      expect(values['vendor'], 'Lavf61.3.104');
      expect(values['field_count'], 1);
    });
  });

  group('FLAC 语义字段', () {
    test('统一词表字段：采样率、位深、声道数、编码标识、时长、平均码率', () {
      final result = parseFlac(_fixture('flac_s16_44100_stereo.normal.flac'));

      final fields = extractFlacFields(result.root);

      expect(_byKey(fields, 'sample_rate')?.value, 44100);
      expect(_byKey(fields, 'sample_rate')?.label, '采样率');
      expect(_byKey(fields, 'sample_rate')?.unit, 'Hz');

      expect(_byKey(fields, 'bit_depth')?.value, 16);
      expect(_byKey(fields, 'bit_depth')?.label, '位深');
      expect(_byKey(fields, 'bit_depth')?.unit, 'bit');

      expect(_byKey(fields, 'channels')?.value, 2);
      expect(_byKey(fields, 'channels')?.label, '声道数');

      expect(_byKey(fields, 'codec')?.value, 'FLAC');
      expect(_byKey(fields, 'codec')?.label, '编码标识');

      expect(_byKey(fields, 'duration')?.value, 0.25);
      expect(_byKey(fields, 'duration')?.label, '时长');
      expect(_byKey(fields, 'duration')?.unit, 's');

      expect(_byKey(fields, 'overall_bitrate')?.value, 11450 * 8 / 0.25);
      expect(_byKey(fields, 'overall_bitrate')?.label, '平均码率');
      expect(_byKey(fields, 'overall_bitrate')?.unit, 'bit/s');
    });

    test('字段来源标出是文件里写的还是推算的', () {
      final result = parseFlac(_fixture('flac_s16_44100_stereo.normal.flac'));

      final fields = extractFlacFields(result.root);

      expect(_byKey(fields, 'sample_rate')?.origin, FieldOrigin.read);
      expect(_byKey(fields, 'sample_rate')?.source, 'FLAC STREAMINFO');
      expect(_byKey(fields, 'duration')?.origin, FieldOrigin.derived);
      expect(_byKey(fields, 'overall_bitrate')?.origin, FieldOrigin.derived);
    });

    test('格式特有字段 total_samples 与 md5 挂在 STREAMINFO 节点上', () {
      final result = parseFlac(_fixture('flac_s16_44100_stereo.normal.flac'));

      final streamInfo = result.root.children.first;
      final totalSamples = _byKey(streamInfo.fields, 'total_samples');
      final md5 = _byKey(streamInfo.fields, 'md5');

      expect(totalSamples?.value, 11025);
      expect(totalSamples?.label, '总采样数');
      expect(md5?.value, 'f71656b039680036049eae0992606cfe');
      expect(md5?.label, 'MD5 校验和');

      // 格式特有字段不进统一词表。
      final unified = extractFlacFields(result.root);
      expect(_byKey(unified, 'total_samples'), isNull);
      expect(_byKey(unified, 'md5'), isNull);
    });
  });

  group('FLAC 截断样本', () {
    test('截断时不抛异常，已读到的结构照常返回', () {
      final result = parseFlac(
        _fixture('flac_s16_44100_stereo.normal.truncated.flac'),
      );

      expect(result.truncated, isTrue);
      expect(result.error, isNotNull);
      expect(result.root.children.map((c) => c.type), [
        'STREAMINFO',
        'VORBIS_COMMENT',
        'PADDING',
      ]);

      // 被截断的块留在树里，长度裁到实际可用的字节数。
      final padding = result.root.children.last;
      expect(padding.isOpaque, isTrue);
      expect(padding.dataSize, 6870 - 94);
      expect(padding.size, 4 + 6870 - 94);
    });

    test('截断样本的语义字段仍然能解出来', () {
      final result = parseFlac(
        _fixture('flac_s16_44100_stereo.normal.truncated.flac'),
      );

      final fields = extractFlacFields(result.root);
      expect(_byKey(fields, 'sample_rate')?.value, 44100);
      expect(_byKey(fields, 'duration')?.value, 0.25);
    });
  });

  group('FLAC 规格表与注册', () {
    test('规格表列出 7 种元数据块', () {
      expect(
        flacContainerSpec.children.keys,
        containsAll(<String>[
          'STREAMINFO',
          'PADDING',
          'APPLICATION',
          'SEEKTABLE',
          'VORBIS_COMMENT',
          'CUESHEET',
          'PICTURE',
        ]),
      );
    });

    test('规格表里 STREAMINFO 是位域、VORBIS_COMMENT 长度字段是小端', () {
      final streamInfo = flacContainerSpec.children['STREAMINFO']!;
      final bitWidths = <String, int?>{
        for (final field in streamInfo.fields)
          if (field.type == FieldType.bits) field.name: field.bitWidth,
      };
      expect(bitWidths['sample_rate'], 20);
      // 规范把声道数与每样本位数存成「真实值减一」，表里的字段名带后缀标明。
      expect(bitWidths['channels_minus_one'], 3);
      expect(bitWidths['bits_per_sample_minus_one'], 5);
      expect(bitWidths['total_samples'], 36);

      final comment = flacContainerSpec.children['VORBIS_COMMENT']!;
      for (final field in comment.fields) {
        if (field.type == FieldType.utf8) continue; // 文本没有字节序
        expect(field.endian, Endian.little, reason: '${field.name} 应为小端');
      }
    });

    test('按内容嗅探认出 FLAC', () {
      expect(isFlacFile(_fixture('flac_s16_44100_stereo.normal.flac')), isTrue);
      expect(
        isFlacFile(_fixture('wav_pcm_s16le_44100_stereo.normal.wav')),
        isFalse,
      );
    });

    test('注册后 detectFormat 按内容选出 FLAC', () {
      clearFormats();
      addTearDown(clearFormats);
      registerFlacFormat();

      final detected = detectFormat(
        _fixture('flac_s16_44100_stereo.normal.flac'),
      );
      expect(detected?.name, 'FLAC');
      expect(detected?.container, same(flacContainerSpec));
      expect(detected?.extractor, isNotNull);
    });

    test('核心的 parseFormat 对 FLAC 走手写解析器', () {
      final result = parseFormat(
        flacFormat,
        _fixture('flac_s16_44100_stereo.normal.flac'),
      );

      expect(result.root.children.map((c) => c.type), [
        'STREAMINFO',
        'VORBIS_COMMENT',
        'PADDING',
      ]);
    });
  });
}
