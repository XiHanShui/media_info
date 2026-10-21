/// 扩展名与实际格式不一致时的提示。
///
/// 覆盖 user story 53、54：
/// 按文件内容判定格式、扩展名与实际格式不符时给出明确提示（是提示不是报错）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/app/extension_check.dart';

void main() {
  group('一致时不提示', () {
    test('wav / WAV', () {
      expect(checkExtension('a.wav', 'WAV'), isNull);
    });

    test('wave 也算 WAV', () {
      expect(checkExtension('a.wave', 'WAV'), isNull);
    });

    test('aiff / AIFF', () {
      expect(checkExtension('a.aiff', 'AIFF'), isNull);
      expect(checkExtension('a.aif', 'AIFF'), isNull);
      expect(checkExtension('a.aifc', 'AIFF'), isNull);
    });

    test('flac / FLAC', () {
      expect(checkExtension('a.flac', 'FLAC'), isNull);
    });

    test('mp3 / MP3', () {
      expect(checkExtension('a.mp3', 'MP3'), isNull);
    });

    test('mp4 / MP4 与 mov / MP4', () {
      expect(checkExtension('a.mp4', 'MP4'), isNull);
      expect(checkExtension('a.m4v', 'MP4'), isNull);
      expect(checkExtension('a.m4a', 'MP4'), isNull);
      expect(checkExtension('a.mov', 'MP4'), isNull);
      expect(checkExtension('a.qt', 'MP4'), isNull);
      expect(checkExtension('a.3gp', 'MP4'), isNull);
      expect(checkExtension('a.3g2', 'MP4'), isNull);
    });

    test('mkv / Matroska', () {
      expect(checkExtension('a.mkv', 'Matroska'), isNull);
      expect(checkExtension('a.mka', 'Matroska'), isNull);
      expect(checkExtension('a.mks', 'Matroska'), isNull);
    });

    test('webm 既是 Matroska 也是 WebM，两者都不提示', () {
      expect(checkExtension('a.webm', 'Matroska'), isNull);
      expect(checkExtension('a.webm', 'WebM'), isNull);
    });
  });

  group('不一致时给出中文提示', () {
    test('提示文案是「扩展名 `.wav` 与实际格式 `MP4` 不符」', () {
      expect(checkExtension('movie.wav', 'MP4'), '扩展名 `.wav` 与实际格式 `MP4` 不符');
    });

    test('反过来也一样：mp4 的内容放在 .wav 里', () {
      expect(checkExtension('a.wav', 'MP4'), '扩展名 `.wav` 与实际格式 `MP4` 不符');
    });

    test('扩展名大写也按小写比较', () {
      expect(checkExtension('a.WAV', 'MP4'), '扩展名 `.wav` 与实际格式 `MP4` 不符');
    });

    test('flac 的内容放在 .mp3 里', () {
      expect(checkExtension('a.mp3', 'FLAC'), '扩展名 `.mp3` 与实际格式 `FLAC` 不符');
    });

    test('Matroska 的内容放在 .mp4 里', () {
      expect(
        checkExtension('a.mp4', 'Matroska'),
        '扩展名 `.mp4` 与实际格式 `Matroska` 不符',
      );
    });

    test('提示里带的是实际检测到的格式名', () {
      expect(checkExtension('a.wav', 'Matroska'), contains('`Matroska`'));
      expect(checkExtension('a.wav', 'FLAC'), contains('`FLAC`'));
    });

    test('路径里的目录不影响判断', () {
      expect(
        checkExtension(r'C:\media\a.wav', 'MP4'),
        '扩展名 `.wav` 与实际格式 `MP4` 不符',
      );
    });
  });

  group('不提示的情况', () {
    test('扩展名不是已知媒体扩展名', () {
      expect(checkExtension('a.bin', 'MP4'), isNull);
      expect(checkExtension('a.txt', 'WAV'), isNull);
      expect(checkExtension('a', 'MP4'), isNull);
    });

    test('没有扩展名', () {
      expect(checkExtension('movie', 'MP4'), isNull);
    });

    test('点开头��隐藏文件没有真正的扩展名', () {
      expect(checkExtension('.wav', 'MP4'), isNull);
    });

    test('结尾是一个孤零零的点', () {
      expect(checkExtension('take1.', 'MP4'), isNull);
    });

    test('检测不出格式时由「无法识别的文件格式」状态负责，不提示', () {
      expect(checkExtension('a.wav', null), isNull);
    });
  });
}
