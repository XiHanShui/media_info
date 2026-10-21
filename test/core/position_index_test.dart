import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/core/byte_source.dart';
import 'package:media_info/src/core/node.dart';
import 'package:media_info/src/app/position_service.dart';
import 'package:media_info/src/core/registry.dart';
import 'package:media_info/src/formats/flac.dart';
import 'package:media_info/src/formats/isobmff.dart';
import 'package:media_info/src/formats/matroska.dart';
import 'package:media_info/src/formats/mp3.dart';
import 'package:media_info/src/formats/riff.dart';


/// 解析一个素材，返回（树、文件级字段）。
({ContainerNode root, List<SemanticField> fields, String format, FormatSpec spec})
_parse(String fileName) {
  final source = FileByteSource.fromPath('test/fixtures/$fileName');
  final FormatSpec spec;
  switch (fileName.split('.').first.split('_').first) {
    case 'wav':
      spec = wavFormat;
    case 'aiff':
      spec = aiffFormat;
    case 'flac':
      spec = flacFormat;
    case 'mp3':
      spec = mp3Format;
    case 'mp4':
    case 'mov':
      spec = mp4Format;
    case 'mkv':
    case 'webm':
      spec = matroskaFormat;
    default:
      throw ArgumentError('未知素材：$fileName');
  }
  final result = parseFormat(spec, source, depth: 8);
  final fields = spec.extractor!(result.root);
  return (root: result.root, fields: fields, format: spec.name, spec: spec);
}

void main() {
  group('WAV / AIFF 的位置索引是精确的', () {
    test('WAV：字节偏移按字节率换算成时间', () {
      final parsed = _parse('wav_pcm_s16le_44100_stereo.normal.wav');
      final index = buildDocumentPositionIndex(parsed.spec, parsed.root, parsed.fields);

      expect(index, isNotNull);
      expect(index!.isExact, isTrue);
      expect(index.duration.inMilliseconds, 250);

      final data = _find(parsed.root, 'data');
      expect(data, isNotNull);

      // 载荷起点 = 0 秒。
      expect(
        index.timestampOf(data!.dataOffset),
        const Duration(microseconds: 0),
      );
      // 往后 0.1 秒（字节率 = 44100 × 2 × 2 = 176400 B/s）。
      // 素材只有 0.25 秒长，所以查 0.1 秒而不是 1 秒。
      final tenth = data.dataOffset + 17640;
      expect(
        index.timestampOf(tenth)?.inMilliseconds,
        closeTo(100, 5),
      );
      // 反向：0.1 秒 → 字节偏移。
      expect(
        index.offsetOf(const Duration(milliseconds: 100)),
        closeTo(tenth, 8),
      );
    });

    test('载荷范围之外返回 null（不猜）', () {
      final parsed = _parse('wav_pcm_s16le_44100_stereo.normal.wav');
      final index = buildDocumentPositionIndex(parsed.spec, parsed.root, parsed.fields)!;

      expect(index.timestampOf(0), isNull);
      expect(index.timestampOf(99999999), isNull);
    });

    test('AIFF：用 采样率 × 声道 × 位深 推出的字节率', () {
      final parsed = _parse('aiff_pcm_s16be_48000_mono.normal.aiff');
      final index = buildDocumentPositionIndex(parsed.spec, parsed.root, parsed.fields);

      expect(index, isNotNull);
      expect(index!.isExact, isTrue);
      final ssnd = _find(parsed.root, 'SSND');
      expect(ssnd, isNotNull);
      // 48000 Hz × 1 声道 × 16 bit = 96000 B/s。
      // 素材只有 0.25 秒长（24000 字节载荷），所以查 0.1 秒。
      final tenth = ssnd!.dataOffset + 9600;
      expect(
        index.timestampOf(tenth)?.inMilliseconds,
        closeTo(100, 5),
      );
      // 反向：0.1 秒 → 字节偏移。
      expect(
        index.offsetOf(const Duration(milliseconds: 100)),
        closeTo(tenth, 8),
      );
    });
  });

  group('MP3 的位置索引是精确的', () {
    test('帧偏移换算成帧的起始时间', () {
      final parsed = _parse('mp3_cbr128_44100_stereo.normal.mp3');
      final index = buildDocumentPositionIndex(parsed.spec, parsed.root, parsed.fields);

      expect(index, isNotNull);
      expect(index!.isExact, isTrue);

      final frames = _findAll(parsed.root, 'MPEG Audio Frame');
      expect(frames.length, greaterThan(1));

      // 第一帧 = 0 秒。
      expect(
        index.timestampOf(frames.first.offset),
        const Duration(microseconds: 0),
      );
      // 第二帧 = 一帧的时长（1152 / 44100 s ≈ 26.1 ms）。
      final second = index.timestampOf(frames[1].offset);
      expect(second, isNotNull);
      expect(second!.inMilliseconds, closeTo(26, 2));

      // 反向：0.1 秒落在某一帧上。
      final offset = index.offsetOf(const Duration(milliseconds: 100));
      expect(offset, isNotNull);
      expect(frames.any((ContainerNode f) => f.offset == offset), isTrue);
    });
  });

  group('MP4 / MOV / Matroska / FLAC 是按比例估算的', () {
    test('MP4：mdat 载荷区间 + 总时长', () {
      final parsed = _parse('mp4_h264_aac_320x240.normal.mp4');
      final index = buildDocumentPositionIndex(parsed.spec, parsed.root, parsed.fields);

      expect(index, isNotNull);
      expect(index!.isExact, isFalse, reason: 'MP4 目前是线性估算');

      final mdat = _find(parsed.root, 'mdat');
      expect(mdat, isNotNull);
      expect(
        index.timestampOf(mdat!.dataOffset),
        const Duration(microseconds: 0),
      );
      // 载荷末尾 ≈ 总时长。
      final end = mdat.dataOffset + mdat.dataSize;
      final nearEnd = index.timestampOf(end - 1);
      expect(nearEnd, isNotNull);
      expect(
        nearEnd!.inMilliseconds,
        closeTo(index.duration.inMilliseconds, 30),
      );
    });

    test('Matroska：Cluster 区间', () {
      final parsed = _parse('mkv_vp9_opus_320x240.normal.mkv');
      final index = buildDocumentPositionIndex(parsed.spec, parsed.root, parsed.fields);

      expect(index, isNotNull);
      expect(index!.isExact, isFalse);
      expect(index.payload, isNotNull);
      expect(index.payload!.length, greaterThan(0));
    });

    test('FLAC：音频帧在最后一个元数据块之后', () {
      final parsed = _parse('flac_s16_44100_stereo.normal.flac');
      final index = buildDocumentPositionIndex(parsed.spec, parsed.root, parsed.fields);

      expect(index, isNotNull);
      expect(index!.isExact, isFalse);
      expect(index.payload, isNotNull);
      // 载荷起点 = 最后一个元数据块的末尾（FLAC 的 PADDING 很大）。
      final last = parsed.root.children.last;
      expect(index.payload!.start, last.offset + last.size);
    });
  });

  group('无法确定时返回 null', () {
    test('读不出时长就没有索引', () {
      final root = ContainerNode(
        type: 'X',
        offset: 0,
        size: 100,
        dataOffset: 0,
        dataSize: 100,
      );
      expect(
        buildDocumentPositionIndex(
          wavFormat,
          root,
          const <SemanticField>[],
        ),
        isNull,
      );
    });

    test('时长为 0 也没有索引', () {
      final root = ContainerNode(
        type: 'X',
        offset: 0,
        size: 100,
        dataOffset: 0,
        dataSize: 100,
      );
      final fields = <SemanticField>[
        const SemanticField(key: 'duration', label: '时长', value: 0.0),
      ];
      expect(
        buildDocumentPositionIndex(wavFormat, root, fields),
        isNull,
      );
    });
  });
}

ContainerNode? _find(ContainerNode root, String type) {
  for (final child in root.children) {
    if (child.type == type) return child;
    final found = _find(child, type);
    if (found != null) return found;
  }
  return null;
}

List<ContainerNode> _findAll(ContainerNode root, String type) {
  final result = <ContainerNode>[];
  void walk(ContainerNode node) {
    for (final child in node.children) {
      if (child.type == type) result.add(child);
      walk(child);
    }
  }

  walk(root);
  return result;
}
