import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/app/extension_check.dart';

void main() {
  group('扩展名与实际格式的一致性', () {
    test('扩展名与检测到的格式不符时给出中文提示', () {
      expect(
        checkExtension('C:\\clips\\take1.wav', 'MP4'),
        '扩展名 `.wav` 与实际格式 `MP4` 不符',
      );
    });

    test('扩展名与检测到的格式一致时不提示', () {
      expect(checkExtension('take1.wav', 'WAV'), isNull);
      expect(checkExtension('take1.mp4', 'MP4'), isNull);
      expect(checkExtension('take1.flac', 'FLAC'), isNull);
      expect(checkExtension('take1.mkv', 'Matroska'), isNull);
    });

    test('扩展名缺失时不提示', () {
      expect(checkExtension('take1', 'MP4'), isNull);
      expect(checkExtension('/tmp/take1.', 'MP4'), isNull);
    });

    test('扩展名不是已知媒体扩展名时不提示', () {
      expect(checkExtension('take1.bin', 'MP4'), isNull);
      expect(checkExtension('take1.txt', 'MP4'), isNull);
    });

    test('无法识别格式时不提示（由「无法识别的文件格式」状态负责）', () {
      expect(checkExtension('take1.wav', null), isNull);
    });

    test('大小写不同也算一致', () {
      expect(checkExtension('TAKE1.WAV', 'WAV'), isNull);
    });

    test('WebM 与 Matroska 互认（同一张 EBML 表）', () {
      expect(checkExtension('take1.webm', 'Matroska'), isNull);
      expect(checkExtension('take1.mkv', 'Matroska'), isNull);
    });
  });
}
