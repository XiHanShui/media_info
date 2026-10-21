import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/core/byte_source.dart';
import 'package:media_info/src/core/node.dart';
import 'package:media_info/src/core/registry.dart';
import 'package:media_info/src/formats/mp3.dart';

import '../core/support/memory_byte_source.dart';

/// 打开一个测试素材（工作目录 = 包根目录）。
FileByteSource _openFixture(String name) =>
    FileByteSource.fromPath('test/fixtures/$name');

void main() {
  group('MP3 结构树', () {
    test('正常样本：根节点下面是 ID3v2 标签与一串帧节点', () {
      final source = _openFixture('mp3_cbr128_44100_stereo.normal.mp3');
      final result = parseMp3(source);
      source.close();

      expect(result.truncated, isFalse);
      expect(result.error, isNull);
      expect(result.root.type, 'MP3');
      expect(result.root.offset, 0);
      expect(result.root.size, 5058);

      final id3 = result.root.children.first;
      expect(id3.type, 'ID3v2');
      expect(id3.offset, 0);
      expect(id3.size, 44);

      final frames = result.root.children.skip(1).toList();
      expect(frames, hasLength(12));
      expect(frames.every((f) => f.type == 'MPEG Audio Frame'), isTrue);
      expect(frames.first.offset, 44);
      expect(frames.first.size, 417);
      expect(frames.last.offset, 4640);
      expect(frames.last.size, 418);
    });

    test('帧节点上挂着这一帧自己的帧头字段', () {
      final source = _openFixture('mp3_cbr128_44100_stereo.normal.mp3');
      final result = parseMp3(source);
      source.close();

      final frame = result.root.children[1];
      expect(frame.type, 'MPEG Audio Frame');
      expect(frame.dataOffset, 48);
      expect(frame.dataSize, 413);

      final fields = {for (final f in frame.fields) f.key: f};
      expect(fields['mpeg_version']?.value, 'MPEG-1');
      expect(fields['mpeg_version']?.label, 'MPEG 版本');
      expect(fields['layer']?.value, 3);
      expect(fields['layer']?.label, '层');
      expect(fields['bitrate']?.value, 128);
      expect(fields['bitrate']?.label, '码率');
      expect(fields['bitrate']?.unit, 'kbps');
      expect(fields['bitrate_mode']?.value, 'CBR');
      expect(fields['bitrate_mode']?.label, '码率模式');
      expect(fields['sample_rate']?.value, 44100);
      expect(fields['sample_rate']?.unit, 'Hz');
      expect(fields['channel_mode']?.value, 'Mono');
      expect(fields['channel_mode']?.label, '声道模式');
      expect(fields['padding']?.value, 0);
      expect(fields['samples_per_frame']?.value, 1152);
      expect(fields['frame_length']?.value, 417);
      expect(fields['crc_protected']?.value, isFalse);
    });

    test('叶子提取器产出统一词表的语义字段', () {
      final source = _openFixture('mp3_cbr128_44100_stereo.normal.mp3');
      final result = parseMp3(source);
      source.close();

      final fields = {for (final f in extractMp3Fields(result.root)) f.key: f};

      expect(fields['codec']?.value, 'MPEG-1 Layer 3');
      expect(fields['codec']?.label, '编码标识');
      expect(fields['sample_rate']?.value, 44100);
      expect(fields['sample_rate']?.unit, 'Hz');
      expect(fields['channels']?.value, 1);
      expect(fields['channels']?.label, '声道数');
      expect(fields['duration']?.value, closeTo(0.313469, 1e-6));
      expect(fields['duration']?.unit, 's');
      expect(fields['duration']?.label, '时长');
      expect(fields['overall_bitrate']?.value, 129084);
      expect(fields['overall_bitrate']?.unit, 'bit/s');
      expect(fields['overall_bitrate']?.origin, FieldOrigin.derived);

      // MP3 没有位深，不产出 bit_depth。
      expect(fields.containsKey('bit_depth'), isFalse);
    });

    test('截断样本：最后一帧留在树里，裁剪到实际有的字节并标记不透明', () {
      final source = _openFixture(
        'mp3_cbr128_44100_stereo.normal.truncated.mp3',
      );
      final result = parseMp3(source);
      source.close();

      expect(result.truncated, isTrue);
      expect(result.error, isNotNull);
      expect(result.error, contains('截断'));

      final frames = result.root.children.skip(1).toList();
      expect(frames, hasLength(8));
      // 前 7 帧是完整的。
      expect(frames.take(7).every((f) => f.isOpaque == false), isTrue);

      // 最后一帧的帧头是好的，但数据被截断了：留在树里，长度裁剪。
      final last = frames.last;
      expect(last.type, 'MPEG Audio Frame');
      expect(last.offset, 2968);
      expect(last.size, 66);
      expect(last.isOpaque, isTrue);

      // 时长只按完整帧算。
      final fields = {for (final f in extractMp3Fields(result.root)) f.key: f};
      expect(fields['duration']?.value, closeTo(0.182857, 1e-6));
    });

    test('VBR 样本：各帧码率不同，码率模式是 VBR', () {
      final source = _openFixture('mp3_vbr_q2_22050_mono.edge.mp3');
      final result = parseMp3(source);
      source.close();

      final frames = result.root.children.skip(1).toList();
      expect(frames, hasLength(13));

      int bitrateOf(dynamic frame) =>
          frame.fields.firstWhere((f) => f.key == 'bitrate').value as int;
      expect(frames.map(bitrateOf).toSet().length, greaterThan(1));
      expect(
        frames.first.fields.firstWhere((f) => f.key == 'bitrate_mode').value,
        'VBR',
      );

      final fields = {for (final f in extractMp3Fields(result.root)) f.key: f};
      expect(fields['codec']?.value, 'MPEG-2 Layer 3');
      expect(fields['sample_rate']?.value, 22050);
      expect(fields['channels']?.value, 1);
      expect(fields['duration']?.value, closeTo(0.339592, 1e-6));
      expect(fields['overall_bitrate']?.value, 43346);
    });

    test('坏帧不终止解析：标记出来之后继续找下一个同步字', () {
      final frame = <int>[0xFF, 0xFB, 0x90, 0xC0, ...List<int>.filled(413, 0)];
      final junk = <int>[0x00, 0x11, 0x22, 0x33, 0x44];
      final source = MemoryByteSource.of([...frame, ...junk, ...frame]);

      final result = parseMp3(source);

      expect(result.truncated, isFalse);
      final children = result.root.children;
      expect(children, hasLength(3));
      expect(children[0].type, 'MPEG Audio Frame');
      expect(children[0].offset, 0);
      expect(children[0].size, 417);
      expect(children[1].type, 'Invalid Frame');
      expect(children[1].offset, 417);
      expect(children[1].size, 5);
      expect(children[1].isOpaque, isTrue);
      expect(children[2].type, 'MPEG Audio Frame');
      expect(children[2].offset, 422);
      expect(children[2].size, 417);
    });

    test('只有帧头没有数据：帧留在树里，长度裁剪到实际有的字节', () {
      final source = MemoryByteSource.of([0xFF, 0xFB, 0x90, 0xC0]);

      final result = parseMp3(source);

      expect(result.truncated, isTrue);
      expect(result.error, contains('截断'));
      final frame = result.root.children.single;
      expect(frame.type, 'MPEG Audio Frame');
      expect(frame.size, 4);
      expect(frame.isOpaque, isTrue);
    });

    test('ID3v2 标签比文件还长：标签留在树里并标记不透明', () {
      // syncsafe 长度 1000 字节，文件只有 20 字节。
      final source = MemoryByteSource.of([
        0x49,
        0x44,
        0x33,
        0x04,
        0x00,
        0x00,
        0x00,
        0x03,
        0xE8,
        0x00,
        ...List<int>.filled(10, 0),
      ]);

      final result = parseMp3(source);

      expect(result.truncated, isTrue);
      expect(result.error, contains('截断'));
      final id3 = result.root.children.single;
      expect(id3.type, 'ID3v2');
      expect(id3.size, 20);
      expect(id3.isOpaque, isTrue);
    });

    test('格式规格带上叶子提取器与嗅探回调', () {
      expect(mp3Format.name, 'MP3');
      expect(mp3Format.extractor, isNotNull);
      expect(mp3Format.detect, isNotNull);

      final source = _openFixture('mp3_cbr128_44100_stereo.normal.mp3');
      final result = parseMp3(source);
      source.close();

      final viaSpec = mp3Format.extractor!(result.root);
      expect(viaSpec.map((f) => f.key), contains('codec'));
      expect(viaSpec.map((f) => f.key), contains('duration'));
    });
  });

  group('MP3 嗅探', () {
    setUp(clearFormats);
    tearDown(clearFormats);

    test('注册后按文件头识别出 MP3', () {
      registerMp3();
      final source = _openFixture('mp3_cbr128_44100_stereo.normal.mp3');
      expect(detectFormat(source)?.name, 'MP3');
      source.close();
    });

    test('重复注册不会重复登记', () {
      registerMp3();
      registerMp3();
      expect(allFormats().where((f) => f.name == 'MP3'), hasLength(1));
    });

    test('文件头是 ID3 就认成 MP3', () {
      registerMp3();
      final source = MemoryByteSource.of([
        0x49,
        0x44,
        0x33,
        0x04,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
      ]);
      expect(detectFormat(source)?.name, 'MP3');
    });

    test('扩展名不符也照样识别成 MP3', () {
      registerMp3();
      final dir = Directory.systemTemp.createTempSync('mp3_detect');
      try {
        final copy = File('${dir.path}/mislabelled.wav');
        File(
          'test/fixtures/mp3_cbr128_44100_stereo.normal.mp3',
        ).copySync(copy.path);
        final source = FileByteSource.fromPath(copy.path);
        expect(detectFormat(source)?.name, 'MP3');
        source.close();
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('不是 MP3 的文件不被 MP3 命中', () {
      registerMp3();
      final source = _openFixture('wav_pcm_s16le_44100_stereo.normal.wav');
      expect(detectFormat(source), isNull);
      source.close();
    });
  });
}
