/// 文件级字段 `track_count`（轨道数）的行为。
///
/// 覆盖 user story 10「我能看到文件里有几条轨道」。
///
/// 关键约束：
/// - 轨道数是**文件级**字段（`scope == FieldScope.file`），位置固定——
///   在 `container_format` 之后，导出 JSON 时顺序稳定；
/// - 数值必须与轨道分组数一致，不能一个说 2 条、另一个说 3 条；
/// - 不是媒体文件时也要有这个字段（值为 0），不能缺。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/app/parse_service.dart';
import 'package:media_info/src/core/node.dart';

import '../support/fixture_paths.dart';

/// 写一个临时文件，返回路径。
String writeTempFile(String name, List<int> bytes) {
  final Directory dir = Directory.systemTemp.createTempSync(
    'media_info_tracks',
  );
  addTearDown(() => dir.deleteSync(recursive: true));
  final File file = File('${dir.path}/$name');
  file.writeAsBytesSync(bytes);
  return file.path;
}

/// 取出文件级字段里的 `track_count`。
SemanticField trackCountOf(ParsedDocument document) {
  final Iterable<SemanticField> matches = document.fileFields.where(
    (SemanticField f) => f.key == 'track_count',
  );
  expect(matches, hasLength(1), reason: 'track_count 必须恰好出现一次');
  return matches.first;
}

void main() {
  group('轨道数的数值', () {
    test('每个有多轨的格式都给出正确的轨道数，且与轨道分组数一致', () {
      const Map<String, int> expectations = <String, int>{
        'mp4_h264_aac_320x240.normal.mp4': 2,
        'mov_mpeg4_aac_320x240.normal.mov': 2,
        'mkv_vp9_opus_320x240.normal.mkv': 2,
        'webm_vp8_vorbis_320x240.normal.webm': 2,
      };

      expectations.forEach((String fileName, int expected) {
        final ParsedDocument document = parseFile(fixturePath(fileName));

        expect(
          trackCountOf(document).value,
          expected,
          reason: '$fileName 的轨道数',
        );
        expect(
          trackCountOf(document).value,
          document.tracks.length,
          reason: '$fileName 的轨道数与轨道分组数必须一致',
        );
      });
    });

    test('只有视频轨的文件，轨道数是 1', () {
      final ParsedDocument document = parseFile(
        fixturePath('mov_video_only_320x240.edge.mov'),
      );

      expect(trackCountOf(document).value, 1);
      expect(document.tracks, hasLength(1));
    });

    test('不是媒体文件时轨道数是 0，不会缺这个字段', () {
      final String path = writeTempFile('not-media.txt', <int>[1, 2, 3, 4]);
      final ParsedDocument document = parseFile(path);

      expect(document.detectedFormat, isNull);
      expect(trackCountOf(document).value, 0);
    });

    test('文件打不开时没有轨道数（连文件级字段都没有）', () {
      final ParsedDocument document = parseFile('G:/media_info/不存在的文件.wav');

      expect(document.fileFields, isEmpty);
    });
  });

  group('轨道数的字段属性', () {
    test('是文件级字段，标签、单位、来源都对', () {
      final ParsedDocument document = parseFile(
        fixturePath('mp4_h264_aac_320x240.normal.mp4'),
      );

      final SemanticField count = trackCountOf(document);
      expect(count.label, '轨道数');
      expect(count.unit, '条');
      expect(count.scope, FieldScope.file);
      expect(count.source, 'tracks');
      expect(count.trackIndex, isNull, reason: '文件级字段不该属于某一条轨道');
    });

    test('位置固定在 container_format 之后', () {
      final ParsedDocument document = parseFile(
        fixturePath('mp4_h264_aac_320x240.normal.mp4'),
      );

      final List<String> keys = document.fileFields
          .map((SemanticField f) => f.key)
          .toList();
      expect(keys.indexOf('track_count'), keys.indexOf('container_format') + 1);
    });

    test('只出现一次——提取器自带的同名键要被移除', () {
      final ParsedDocument document = parseFile(
        fixturePath('mkv_vp9_opus_320x240.normal.mkv'),
      );

      expect(
        document.fileFields.where((SemanticField f) => f.key == 'track_count'),
        hasLength(1),
      );
    });

    test('每个文件都带着它——不因为格式不同就少一个字段', () {
      const Map<String, int> expectations = <String, int>{
        'wav_pcm_s16le_44100_stereo.normal.wav': 1,
        'aiff_pcm_s16be_48000_mono.normal.aiff': 1,
        'flac_s16_44100_stereo.normal.flac': 1,
        'mp3_cbr128_44100_stereo.normal.mp3': 1,
        'mp4_h264_aac_320x240.normal.mp4': 2,
        'mov_mpeg4_aac_320x240.normal.mov': 2,
        'mkv_vp9_opus_320x240.normal.mkv': 2,
        'webm_vp8_vorbis_320x240.normal.webm': 2,
      };

      expectations.forEach((String fileName, int expected) {
        final ParsedDocument document = parseFile(fixturePath(fileName));
        expect(
          trackCountOf(document).value,
          expected,
          reason: '$fileName 的轨道数',
        );
      });
    });
  });
}
