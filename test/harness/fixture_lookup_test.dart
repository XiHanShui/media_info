import 'package:flutter_test/flutter_test.dart';

import '../support/fixture_paths.dart';

void main() {
  group('素材文件名解析', () {
    test('正常素材：<格式>_<参数>.<类别>.<扩展名>', () {
      final name = parseFixtureName('wav_pcm_s16le_44100_stereo.normal.wav');

      expect(name.format, 'wav');
      expect(name.params, 'pcm_s16le_44100_stereo');
      expect(name.category, FixtureCategory.normal);
      expect(name.extension, 'wav');
      expect(name.baseName, 'wav_pcm_s16le_44100_stereo');
    });

    test('损坏素材：基名里多一段 normal', () {
      final name = parseFixtureName(
        'mp4_h264_aac_320x240.normal.truncated.mp4',
      );

      expect(name.format, 'mp4');
      expect(name.params, 'h264_aac_320x240');
      expect(name.category, FixtureCategory.truncated);
      expect(name.extension, 'mp4');
      expect(name.baseName, 'mp4_h264_aac_320x240.normal');
    });

    test('长度字段撒谎的素材', () {
      final name = parseFixtureName(
        'wav_pcm_s16le_44100_stereo.normal.liesize.wav',
      );

      expect(name.format, 'wav');
      expect(name.params, 'pcm_s16le_44100_stereo');
      expect(name.category, FixtureCategory.liesize);
      expect(name.extension, 'wav');
    });

    test('边界素材', () {
      final name = parseFixtureName('mkv_vp9_noaudio_320x240.edge.mkv');

      expect(name.format, 'mkv');
      expect(name.params, 'vp9_noaudio_320x240');
      expect(name.category, FixtureCategory.edge);
      expect(name.extension, 'mkv');
    });

    test('类别不认识时抛 FormatException', () {
      expect(() => parseFixtureName('wav_x.broken.wav'), throwsFormatException);
    });

    test('文件名太短时抛 FormatException', () {
      expect(() => parseFixtureName('wav'), throwsFormatException);
    });
  });

  group('素材定位', () {
    test('目录里有 26 个素材，文件名都符合命名约定', () {
      final names = listFixtureNames();

      expect(names, hasLength(26));
      expect(names, orderedEquals(List<String>.from(names)..sort()));
      for (final name in names) {
        final parsed = parseFixtureName(name);
        expect(
          parsed.format,
          isIn(<String>[
            'wav',
            'aiff',
            'flac',
            'mp3',
            'mp4',
            'mov',
            'mkv',
            'webm',
          ]),
          reason: name,
        );
        expect(parsed.category, isIn(FixtureCategory.values), reason: name);
      }
    });

    test('fixturePath 指向真实存在的文件', () {
      final path = fixturePath('wav_pcm_s16le_44100_stereo.normal.wav');

      expect(path, 'test/fixtures/wav_pcm_s16le_44100_stereo.normal.wav');
      expect(fixtureFile(path.split('/').last).existsSync(), isTrue);
    });

    test('fixtureSource 打开的是文件本身，长度一致', () {
      final source = fixtureSource('wav_pcm_s16le_44100_stereo.normal.wav');
      addTearDown(source.close);

      expect(source.length, 44178);
      expect(source.read(0, 4), <int>[0x52, 0x49, 0x46, 0x46]); // 'RIFF'
    });

    test('素材不存在时抛 StateError，并把现有素材列出来', () {
      expect(
        () => fixturePath('wav_not_here.normal.wav'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('素材不存在'),
          ),
        ),
      );
    });

    test('按格式与类别查找素材', () {
      expect(
        findFixtureName('mp4', FixtureCategory.normal),
        'mp4_h264_aac_320x240.normal.mp4',
      );
      expect(
        findFixtureName('mp4', FixtureCategory.truncated),
        'mp4_h264_aac_320x240.normal.truncated.mp4',
      );
      expect(findFixtureName('mp4', FixtureCategory.liesize), isNull);
    });

    test('找不到素材时 requireFixtureName 抛 StateError', () {
      expect(
        () => requireFixtureName('mp4', FixtureCategory.liesize),
        throwsA(isA<StateError>()),
      );
      expect(
        requireFixturePath('flac', FixtureCategory.normal),
        'test/fixtures/flac_s16_44100_stereo.normal.flac',
      );
    });
  });
}
