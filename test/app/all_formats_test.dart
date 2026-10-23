import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/core/byte_source.dart';
import 'package:media_info/src/core/registry.dart';
import 'package:media_info/src/formats/all_formats.dart';

/// 打开一个素材文件。
FileByteSource _fixture(String name) =>
    FileByteSource.fromPath('test/fixtures/$name');

void main() {
  group('全部格式的注册', () {
    setUp(registerAllFormats);

    test('五个格式模块都注册进注册表', () {
      final names = allFormats().map((format) => format.name).toSet();
      expect(
        names,
        containsAll(<String>['WAV', 'AIFF', 'MP4', 'FLAC', 'Matroska', 'MP3']),
      );
    });

    test('嗅探按内容判定，不看扩展名', () {
      final cases = <String, String>{
        'wav_pcm_s16le_44100_stereo.normal.wav': 'WAV',
        'aiff_pcm_s16be_48000_mono.normal.aiff': 'AIFF',
        'flac_s16_44100_stereo.normal.flac': 'FLAC',
        'mp3_cbr128_44100_stereo.normal.mp3': 'MP3',
        'mp4_h264_aac_320x240.normal.mp4': 'MP4',
        'mkv_vp9_opus_320x240.normal.mkv': 'Matroska',
      };
      cases.forEach((fixture, expected) {
        final source = _fixture(fixture);
        addTearDown(source.close);
        expect(detectFormat(source)?.name, expected, reason: fixture);
      });
    });

    test('重复注册安全', () {
      registerAllFormats();
      registerAllFormats();
      expect(allFormats().length, 6);
    });
  });
}
