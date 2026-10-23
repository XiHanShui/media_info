/// 各格式的**语义字段**断言。
///
/// 覆盖 user story 8–15、29–40、53：
/// 时长、文件大小与推算码率、轨道数、codec 标识、分辨率与帧率、
/// 采样率 / 位深 / 声道数、字段分组、推算标记、格式覆盖度。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/app/parse_service.dart';
import 'package:media_info/src/core/node.dart';

import '../support/fixture_paths.dart';

/// 字段表（key → 值）。
Map<String, Object?> valuesOf(List<SemanticField> fields) => <String, Object?>{
  for (final SemanticField field in fields) field.key: field.value,
};

/// 找某个 key 的字段。
SemanticField? fieldOf(List<SemanticField> fields, String key) {
  for (final SemanticField field in fields) {
    if (field.key == key) return field;
  }
  return null;
}

/// 解析一个素材（走应用层的解析服务）。
ParsedDocument parseFixture(String fileName) =>
    parseFile(fixturePath(fileName));

void main() {
  group('WAV', () {
    test('文件级字段：file_name / file_size / container_format 各只有一个', () {
      final ParsedDocument doc = parseFixture(
        'wav_pcm_s16le_44100_stereo.normal.wav',
      );

      expect(doc.detectedFormat, 'WAV');
      final List<String> keys = doc.fileFields
          .map((SemanticField f) => f.key)
          .toList();
      expect(keys.where((String k) => k == 'file_name'), hasLength(1));
      expect(keys.where((String k) => k == 'file_size'), hasLength(1));
      expect(keys.where((String k) => k == 'container_format'), hasLength(1));
      expect(keys.take(3), <String>[
        'file_name',
        'file_size',
        'container_format',
      ]);
    });

    test('文件大小是文件的真实字节数，单位是 byte', () {
      final ParsedDocument doc = parseFixture(
        'wav_pcm_s16le_44100_stereo.normal.wav',
      );

      final SemanticField size = fieldOf(doc.fileFields, 'file_size')!;
      expect(size.value, 44178);
      expect(size.unit, 'byte');
      expect(size.label, '文件大小');
      expect(size.source, 'file');
    });

    test('容器格式是 WAV', () {
      final ParsedDocument doc = parseFixture(
        'wav_pcm_s16le_44100_stereo.normal.wav',
      );

      expect(fieldOf(doc.fileFields, 'container_format')!.value, 'WAV');
    });

    test('轨道级字段：采样率 / 位深 / 声道数 / codec', () {
      final ParsedDocument doc = parseFixture(
        'wav_pcm_s16le_44100_stereo.normal.wav',
      );

      expect(doc.tracks, hasLength(1));
      final List<SemanticField> fields = doc.tracks.single.fields;
      expect(fieldOf(fields, 'sample_rate')!.value, 44100);
      expect(fieldOf(fields, 'sample_rate')!.unit, 'Hz');
      expect(fieldOf(fields, 'bit_depth')!.value, 16);
      expect(fieldOf(fields, 'bit_depth')!.unit, 'bit');
      expect(fieldOf(fields, 'channels')!.value, 2);
      expect(fieldOf(fields, 'codec')!.value, 'PCM');
      expect(fieldOf(fields, 'codec')!.label, '编码标识');
    });

    test('时长是 0.25 秒，来源是文件里写的数据', () {
      final ParsedDocument doc = parseFixture(
        'wav_pcm_s16le_44100_stereo.normal.wav',
      );

      final SemanticField duration = fieldOf(doc.fileFields, 'duration')!;
      expect(duration.value, 0.25);
      expect(duration.unit, 's');
      expect(duration.origin, FieldOrigin.read);
    });

    test('平均码率是推算值', () {
      final ParsedDocument doc = parseFixture(
        'wav_pcm_s16le_44100_stereo.normal.wav',
      );

      final SemanticField bitrate = fieldOf(doc.fileFields, 'overall_bitrate')!;
      expect(bitrate.origin, FieldOrigin.derived);
      expect(bitrate.unit, 'bit/s');
      expect(bitrate.value, 1413696);
    });

    test('24bit 边界样本：EXTENSIBLE、24bit、48kHz', () {
      final ParsedDocument doc = parseFixture(
        'wav_pcm_s24le_48000_stereo.edge.wav',
      );

      final List<SemanticField> fields = doc.tracks.single.fields;
      expect(fieldOf(fields, 'codec')!.value, 'EXTENSIBLE');
      expect(fieldOf(fields, 'bit_depth')!.value, 24);
      expect(fieldOf(fields, 'sample_rate')!.value, 48000);
    });

    test('8bit 单声道边界样本', () {
      final ParsedDocument doc = parseFixture('wav_pcm_u8_8000_mono.edge.wav');

      final List<SemanticField> fields = doc.tracks.single.fields;
      expect(fieldOf(fields, 'bit_depth')!.value, 8);
      expect(fieldOf(fields, 'channels')!.value, 1);
      expect(fieldOf(fields, 'sample_rate')!.value, 8000);
    });
  });

  group('AIFF', () {
    test('容器格式是 AIFF', () {
      final ParsedDocument doc = parseFixture(
        'aiff_pcm_s16be_48000_mono.normal.aiff',
      );

      expect(doc.detectedFormat, 'AIFF');
      expect(fieldOf(doc.fileFields, 'container_format')!.value, 'AIFF');
    });

    test('轨道级字段：采样率 / 位深 / 声道数', () {
      final ParsedDocument doc = parseFixture(
        'aiff_pcm_s16be_48000_mono.normal.aiff',
      );

      final List<SemanticField> fields = doc.tracks.single.fields;
      expect(fieldOf(fields, 'sample_rate')!.value, 48000);
      expect(fieldOf(fields, 'bit_depth')!.value, 16);
      expect(fieldOf(fields, 'channels')!.value, 1);
    });

    test('codec 是 NONE，并且被标成推算值', () {
      final ParsedDocument doc = parseFixture(
        'aiff_pcm_s16be_48000_mono.normal.aiff',
      );

      final SemanticField codec = fieldOf(doc.tracks.single.fields, 'codec')!;
      expect(codec.value, 'NONE');
      expect(codec.origin, FieldOrigin.derived);
    });

    test('时长由采样帧数与采样率算出', () {
      final ParsedDocument doc = parseFixture(
        'aiff_pcm_s16be_48000_mono.normal.aiff',
      );

      expect(fieldOf(doc.fileFields, 'duration')!.value, 0.25);
    });
  });

  group('FLAC', () {
    test('容器格式是 FLAC，codec 是 FLAC', () {
      final ParsedDocument doc = parseFixture(
        'flac_s16_44100_stereo.normal.flac',
      );

      expect(doc.detectedFormat, 'FLAC');
      expect(fieldOf(doc.fileFields, 'container_format')!.value, 'FLAC');
      expect(fieldOf(doc.tracks.single.fields, 'codec')!.value, 'FLAC');
    });

    test('轨道级字段：采样率 / 位深 / 声道数', () {
      final ParsedDocument doc = parseFixture(
        'flac_s16_44100_stereo.normal.flac',
      );

      final List<SemanticField> fields = doc.tracks.single.fields;
      expect(fieldOf(fields, 'sample_rate')!.value, 44100);
      expect(fieldOf(fields, 'bit_depth')!.value, 16);
      expect(fieldOf(fields, 'channels')!.value, 2);
    });

    test('时长是推算值（由总采样数与采样率算出）', () {
      final ParsedDocument doc = parseFixture(
        'flac_s16_44100_stereo.normal.flac',
      );

      final SemanticField duration = fieldOf(doc.fileFields, 'duration')!;
      expect(duration.value, 0.25);
      expect(duration.origin, FieldOrigin.derived);
    });

    test('平均码率是推算值', () {
      final ParsedDocument doc = parseFixture(
        'flac_s16_44100_stereo.normal.flac',
      );

      expect(
        fieldOf(doc.fileFields, 'overall_bitrate')!.origin,
        FieldOrigin.derived,
      );
    });
  });

  group('MP3', () {
    test('容器格式是 MP3，codec 是 MPEG-1 Layer 3', () {
      final ParsedDocument doc = parseFixture(
        'mp3_cbr128_44100_stereo.normal.mp3',
      );

      expect(doc.detectedFormat, 'MP3');
      expect(fieldOf(doc.fileFields, 'container_format')!.value, 'MP3');
      expect(
        fieldOf(doc.tracks.single.fields, 'codec')!.value,
        'MPEG-1 Layer 3',
      );
    });

    test('轨道级字段：采样率与声道数', () {
      final ParsedDocument doc = parseFixture(
        'mp3_cbr128_44100_stereo.normal.mp3',
      );

      final List<SemanticField> fields = doc.tracks.single.fields;
      expect(fieldOf(fields, 'sample_rate')!.value, 44100);
      expect(fieldOf(fields, 'channels')!.value, 2);
    });

    test('时长由帧列表算出', () {
      final ParsedDocument doc = parseFixture(
        'mp3_cbr128_44100_stereo.normal.mp3',
      );

      final SemanticField duration = fieldOf(doc.fileFields, 'duration')!;
      expect(duration.value, closeTo(0.313469, 1e-6));
      expect(duration.unit, 's');
    });

    test('VBR 边界样本：codec 变成 MPEG-2 Layer 3', () {
      final ParsedDocument doc = parseFixture('mp3_vbr_q2_22050_mono.edge.mp3');

      expect(
        fieldOf(doc.tracks.single.fields, 'codec')!.value,
        'MPEG-2 Layer 3',
      );
      expect(fieldOf(doc.tracks.single.fields, 'sample_rate')!.value, 22050);
    });
  });

  group('MP4', () {
    test('容器格式取 ftyp 的主品牌 isom', () {
      final ParsedDocument doc = parseFixture(
        'mp4_h264_aac_320x240.normal.mp4',
      );

      expect(doc.detectedFormat, 'MP4');
      expect(fieldOf(doc.fileFields, 'container_format')!.value, 'isom');
      expect(fieldOf(doc.fileFields, 'container_format')!.source, 'ftyp');
      expect(fieldOf(doc.fileFields, 'brand')!.value, 'isom');
    });

    test('时长 1.0 秒，时间刻度 1000 tick', () {
      final ParsedDocument doc = parseFixture(
        'mp4_h264_aac_320x240.normal.mp4',
      );

      expect(fieldOf(doc.fileFields, 'duration')!.value, 1.0);
      expect(fieldOf(doc.fileFields, 'timescale')!.value, 1000);
      expect(fieldOf(doc.fileFields, 'timescale')!.unit, 'tick');
    });

    test('平均码率是推算值', () {
      final ParsedDocument doc = parseFixture(
        'mp4_h264_aac_320x240.normal.mp4',
      );

      final SemanticField bitrate = fieldOf(doc.fileFields, 'overall_bitrate')!;
      expect(bitrate.origin, FieldOrigin.derived);
      expect(bitrate.value, closeTo(93264, 0.5));
    });

    test('兼容品牌展开成四个 fourcc', () {
      final ParsedDocument doc = parseFixture(
        'mp4_h264_aac_320x240.normal.mp4',
      );

      expect(fieldOf(doc.fileFields, 'compatible_brands')!.value, <String>[
        'isom',
        'iso2',
        'avc1',
        'mp41',
      ]);
    });

    test('视频轨道：类型 / codec / 分辨率 / 帧率', () {
      final ParsedDocument doc = parseFixture(
        'mp4_h264_aac_320x240.normal.mp4',
      );

      final List<SemanticField> fields = doc.tracks[0].fields;
      expect(doc.tracks[0].trackIndex, 0);
      expect(fieldOf(fields, 'track_type')!.value, 'video');
      expect(fieldOf(fields, 'codec')!.value, 'avc1');
      expect(fieldOf(fields, 'width')!.value, 320);
      expect(fieldOf(fields, 'width')!.unit, 'px');
      expect(fieldOf(fields, 'height')!.value, 240);
      expect(fieldOf(fields, 'frame_rate')!.value, 25.0);
      expect(fieldOf(fields, 'frame_rate')!.unit, 'fps');
    });

    test('音频轨道：codec / 采样率 / 位深 / 声道数', () {
      final ParsedDocument doc = parseFixture(
        'mp4_h264_aac_320x240.normal.mp4',
      );

      final List<SemanticField> fields = doc.tracks[1].fields;
      expect(doc.tracks[1].trackIndex, 1);
      expect(fieldOf(fields, 'track_type')!.value, 'audio');
      expect(fieldOf(fields, 'codec')!.value, 'mp4a');
      expect(fieldOf(fields, 'sample_rate')!.value, 44100);
      expect(fieldOf(fields, 'bit_depth')!.value, 16);
      expect(fieldOf(fields, 'channels')!.value, 1);
    });

    test('两条轨道的字段都列出来，一条都不漏', () {
      final ParsedDocument doc = parseFixture(
        'mp4_h264_aac_320x240.normal.mp4',
      );

      expect(doc.tracks, hasLength(2));
      expect(doc.tracks.map((TrackFields t) => t.trackIndex), <int>[0, 1]);
      for (final TrackFields track in doc.tracks) {
        expect(track.fields, isNotEmpty);
        for (final SemanticField field in track.fields) {
          expect(field.scope, FieldScope.track);
          expect(field.trackIndex, track.trackIndex);
        }
      }
    });

    test('没有音轨的边界样本只有一条轨道', () {
      final ParsedDocument doc = parseFixture(
        'mp4_h264_noaudio_320x240.edge.mp4',
      );

      expect(doc.tracks, hasLength(1));
      expect(fieldOf(doc.tracks.single.fields, 'track_type')!.value, 'video');
    });
  });

  group('MOV', () {
    test('容器格式取 ftyp 的主品牌 qt', () {
      final ParsedDocument doc = parseFixture(
        'mov_mpeg4_aac_320x240.normal.mov',
      );

      expect(doc.detectedFormat, 'MP4');
      expect(fieldOf(doc.fileFields, 'container_format')!.value, 'qt  ');
    });

    test('视频轨道的 codec 是 mp4v，时长 1.0 秒', () {
      final ParsedDocument doc = parseFixture(
        'mov_mpeg4_aac_320x240.normal.mov',
      );

      expect(fieldOf(doc.fileFields, 'duration')!.value, 1.0);
      expect(fieldOf(doc.tracks[0].fields, 'codec')!.value, 'mp4v');
      expect(fieldOf(doc.tracks[0].fields, 'frame_rate')!.value, 25.0);
    });
  });

  group('MKV', () {
    test('容器格式取 EBML 的 DocType（matroska）', () {
      final ParsedDocument doc = parseFixture(
        'mkv_vp9_opus_320x240.normal.mkv',
      );

      expect(doc.detectedFormat, 'Matroska');
      expect(fieldOf(doc.fileFields, 'container_format')!.value, 'matroska');
    });

    test('文件大小只有一个（提取器带来的那一个被解析服务替换掉）', () {
      final ParsedDocument doc = parseFixture(
        'mkv_vp9_opus_320x240.normal.mkv',
      );

      final List<SemanticField> sizes = doc.fileFields
          .where((SemanticField f) => f.key == 'file_size')
          .toList();
      expect(sizes, hasLength(1));
      expect(sizes.single.value, 17487);
      expect(sizes.single.unit, 'byte');
    });

    test('时长与时间戳刻度', () {
      final ParsedDocument doc = parseFixture(
        'mkv_vp9_opus_320x240.normal.mkv',
      );

      expect(fieldOf(doc.fileFields, 'duration')!.value, 1.0);
      expect(fieldOf(doc.fileFields, 'timestamp_scale')!.value, 1000000);
    });

    test('视频轨道：V_VP9、320x240', () {
      final ParsedDocument doc = parseFixture(
        'mkv_vp9_opus_320x240.normal.mkv',
      );

      final List<SemanticField> fields = doc.tracks[0].fields;
      expect(fieldOf(fields, 'track_type')!.value, 'video');
      expect(fieldOf(fields, 'codec')!.value, 'V_VP9');
      expect(fieldOf(fields, 'width')!.value, 320);
      expect(fieldOf(fields, 'height')!.value, 240);
    });

    test('音频轨道：A_OPUS、48kHz、1 声道、16bit', () {
      final ParsedDocument doc = parseFixture(
        'mkv_vp9_opus_320x240.normal.mkv',
      );

      final List<SemanticField> fields = doc.tracks[1].fields;
      expect(fieldOf(fields, 'track_type')!.value, 'audio');
      expect(fieldOf(fields, 'codec')!.value, 'A_OPUS');
      expect(fieldOf(fields, 'sample_rate')!.value, 48000);
      expect(fieldOf(fields, 'channels')!.value, 1);
      expect(fieldOf(fields, 'bit_depth')!.value, 16);
    });

    test('Matroska 的帧率从 DefaultDuration 换算出来（FrameRate 没写时）', () {
      final ParsedDocument doc = parseFixture(
        'mkv_vp9_opus_320x240.normal.mkv',
      );

      // MKV 没写 Video/FrameRate（0x2383E3），但写了
      // TrackEntry/DefaultDuration（每帧多少纳秒）——帧率 = 1e9 / DefaultDuration。
      final SemanticField? frameRate = fieldOf(doc.tracks[0].fields, 'frame_rate');
      expect(frameRate, isNotNull, reason: '帧率应该由 DefaultDuration 换算出来');
      expect(frameRate!.value, 25.0);
      expect(frameRate.unit, 'fps');
      expect(frameRate.source, 'TrackEntry/DefaultDuration');
      expect(fieldOf(doc.tracks[0].fields, 'width')!.value, 320);
      expect(fieldOf(doc.tracks[0].fields, 'height')!.value, 240);
    });
  });

  group('WebM', () {
    test('容器格式取 EBML 的 DocType（webm）', () {
      final ParsedDocument doc = parseFixture(
        'webm_vp8_vorbis_320x240.normal.webm',
      );

      expect(doc.detectedFormat, 'Matroska');
      expect(fieldOf(doc.fileFields, 'container_format')!.value, 'webm');
    });

    test('时长 1.003 秒', () {
      final ParsedDocument doc = parseFixture(
        'webm_vp8_vorbis_320x240.normal.webm',
      );

      expect(fieldOf(doc.fileFields, 'duration')!.value, 1.003);
    });

    test('视频 V_VP8、音频 A_VORBIS（44.1kHz / 32bit）', () {
      final ParsedDocument doc = parseFixture(
        'webm_vp8_vorbis_320x240.normal.webm',
      );

      expect(fieldOf(doc.tracks[0].fields, 'codec')!.value, 'V_VP8');
      expect(fieldOf(doc.tracks[1].fields, 'codec')!.value, 'A_VORBIS');
      expect(fieldOf(doc.tracks[1].fields, 'sample_rate')!.value, 44100);
      expect(fieldOf(doc.tracks[1].fields, 'bit_depth')!.value, 32);
    });
  });

  group('损坏文件：字段缺席与在场', () {
    test('MP4 被截断：读不到 mvhd，所以没有时长', () {
      final ParsedDocument doc = parseFixture(
        'mp4_h264_aac_320x240.normal.truncated.mp4',
      );

      expect(doc.truncated, isTrue);
      expect(doc.error, isNotNull);
      expect(fieldOf(doc.fileFields, 'duration'), isNull);
      expect(doc.tracks, isEmpty);
      // 但仍然给得出文件级的三件套。
      expect(fieldOf(doc.fileFields, 'file_name'), isNotNull);
      expect(fieldOf(doc.fileFields, 'file_size')!.value, 6994);
      expect(fieldOf(doc.fileFields, 'container_format')!.value, 'isom');
    });

    test('WebM 被截断：没有时长，但有容器格式', () {
      final ParsedDocument doc = parseFixture(
        'webm_vp8_vorbis_320x240.normal.truncated.webm',
      );

      expect(doc.truncated, isTrue);
      expect(fieldOf(doc.fileFields, 'duration'), isNull);
      expect(fieldOf(doc.fileFields, 'container_format')!.value, 'webm');
    });

    test('不是媒体文件：不是错误，而是「识别不出格式」', () {
      final ParsedDocument doc = parseFile('test/fixtures/does_not_exist.mp4');

      expect(doc.detectedFormat, isNull);
      expect(doc.error, '文件不存在');
      expect(doc.root, isNull);
      expect(doc.tracks, isEmpty);
    });
  });

  group('统一词表的一致性', () {
    const List<String> unifiedKeys = <String>[
      'file_name',
      'file_size',
      'container_format',
      'duration',
      'overall_bitrate',
      'track_index',
      'track_type',
      'codec',
      'width',
      'height',
      'frame_rate',
      'sample_rate',
      'bit_depth',
      'channels',
      'language',
    ];

    test('每个格式都有 file_name / file_size / container_format 三个中央键', () {
      const List<String> fixtures = <String>[
        'wav_pcm_s16le_44100_stereo.normal.wav',
        'aiff_pcm_s16be_48000_mono.normal.aiff',
        'flac_s16_44100_stereo.normal.flac',
        'mp3_cbr128_44100_stereo.normal.mp3',
        'mp4_h264_aac_320x240.normal.mp4',
        'mov_mpeg4_aac_320x240.normal.mov',
        'mkv_vp9_opus_320x240.normal.mkv',
        'webm_vp8_vorbis_320x240.normal.webm',
      ];

      for (final String fixture in fixtures) {
        final ParsedDocument doc = parseFixture(fixture);
        final List<String> keys = doc.fileFields
            .map((SemanticField f) => f.key)
            .toList();
        for (final String key in <String>[
          'file_name',
          'file_size',
          'container_format',
        ]) {
          expect(
            keys.where((String k) => k == key),
            hasLength(1),
            reason: '$fixture 的 $key 应该恰好出现一次',
          );
        }
      }
    });

    test('所有字段都有非空的中文显示名', () {
      const List<String> fixtures = <String>[
        'wav_pcm_s16le_44100_stereo.normal.wav',
        'mp4_h264_aac_320x240.normal.mp4',
        'mkv_vp9_opus_320x240.normal.mkv',
      ];

      for (final String fixture in fixtures) {
        final ParsedDocument doc = parseFixture(fixture);
        for (final SemanticField field in doc.fileFields) {
          expect(field.label, isNotEmpty, reason: '$fixture 的 ${field.key}');
        }
        for (final TrackFields track in doc.tracks) {
          for (final SemanticField field in track.fields) {
            expect(field.label, isNotEmpty, reason: '$fixture 的 ${field.key}');
          }
        }
      }
    });

    test('统一词表里的键确实被产出（不是写在词表里没人用）', () {
      final Set<String> produced = <String>{};
      const List<String> fixtures = <String>[
        'wav_pcm_s16le_44100_stereo.normal.wav',
        'aiff_pcm_s16be_48000_mono.normal.aiff',
        'flac_s16_44100_stereo.normal.flac',
        'mp3_cbr128_44100_stereo.normal.mp3',
        'mp4_h264_aac_320x240.normal.mp4',
        'mov_mpeg4_aac_320x240.normal.mov',
        'mkv_vp9_opus_320x240.normal.mkv',
        'webm_vp8_vorbis_320x240.normal.webm',
      ];

      for (final String fixture in fixtures) {
        final ParsedDocument doc = parseFixture(fixture);
        produced.addAll(doc.fileFields.map((SemanticField f) => f.key));
        for (final TrackFields track in doc.tracks) {
          produced.addAll(track.fields.map((SemanticField f) => f.key));
        }
      }

      for (final String key in unifiedKeys) {
        expect(produced, contains(key), reason: '统一词表里的 $key 没有被任何格式产出');
      }
    });
  });
}
