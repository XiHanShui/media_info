import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/app/parse_service.dart';
import 'package:media_info/src/core/node.dart';

/// 素材文件（相对包根目录）。
const String wavFixture = 'test/fixtures/wav_pcm_s16le_44100_stereo.normal.wav';
const String mp4Fixture = 'test/fixtures/mp4_h264_aac_320x240.normal.mp4';

/// 在临时目录里放一个文件，返回路径。
String _tempFile(String name, List<int> bytes) {
  final dir = Directory.systemTemp.createTempSync('media_info_app_test');
  addTearDown(() => dir.deleteSync(recursive: true));
  final file = File('${dir.path}/$name');
  file.writeAsBytesSync(bytes);
  return file.path;
}

/// 按 key 找字段。
SemanticField? _byKey(List<SemanticField> fields, String key) {
  for (final field in fields) {
    if (field.key == key) return field;
  }
  return null;
}

void main() {
  group('解析服务', () {
    test('按内容识别格式：WAV 文件被认成 WAV', () {
      final document = parseFile(wavFixture);
      expect(document.detectedFormat, 'WAV');
      expect(document.error, isNull);
      expect(document.truncated, isFalse);
      expect(document.root, isNotNull);
    });

    test('文件级字段由解析服务统一补齐：文件名 / 文件大小 / 容器格式', () {
      final document = parseFile(wavFixture);
      final fileName = _byKey(document.fileFields, 'file_name');
      final fileSize = _byKey(document.fileFields, 'file_size');
      final containerFormat = _byKey(document.fileFields, 'container_format');

      expect(fileName!.label, '文件名');
      expect(fileName.value, 'wav_pcm_s16le_44100_stereo.normal.wav');
      expect(fileSize!.label, '文件大小');
      expect(fileSize.unit, 'byte');
      expect(fileSize.value, File(wavFixture).lengthSync());
      expect(containerFormat!.label, '容器格式');
      expect(containerFormat.value, 'WAV');
    });

    test('轨道级字段按轨道分组', () {
      final document = parseFile(wavFixture);
      expect(document.tracks.length, 1);

      final track = document.tracks.first;
      expect(track.trackIndex, 0);
      expect(_byKey(track.fields, 'sample_rate')!.value, 44100);
      expect(_byKey(track.fields, 'bit_depth')!.value, 16);
      expect(_byKey(track.fields, 'channels')!.value, 2);
    });

    test('推算字段带 derived 来源', () {
      final document = parseFile(wavFixture);
      final bitrate = _byKey(document.fileFields, 'overall_bitrate');
      expect(bitrate, isNotNull);
      expect(bitrate!.origin, FieldOrigin.derived);
    });

    test('文件不存在时给出中文错误，不影响其它标签', () {
      final document = parseFile('test/fixtures/does_not_exist.wav');
      expect(document.error, '文件不存在');
      expect(document.detectedFormat, isNull);
      expect(document.root, isNull);
    });

    test('不是媒体的文件无法识别（不报错、不崩溃）', () {
      final path = _tempFile('notes.txt', '这是一段普通文本，不是媒体文件。'.codeUnits);
      final document = parseFile(path);
      expect(document.detectedFormat, isNull);
      expect(document.error, isNull);
      expect(document.extensionWarning, isNull);
    });

    test('扩展名与实际格式不符时给出警告', () {
      final bytes = File(mp4Fixture).readAsBytesSync();
      final path = _tempFile('mislabelled.wav', bytes);
      final document = parseFile(path);
      expect(document.detectedFormat, 'MP4');
      expect(document.extensionWarning, '扩展名 `.wav` 与实际格式 `MP4` 不符');
    });

    test('文件大小与实际文件长度一致（每种格式都一样）', () {
      const fixtures = <String>[
        'wav_pcm_s16le_44100_stereo.normal.wav',
        'aiff_pcm_s16be_48000_mono.normal.aiff',
        'flac_s16_44100_stereo.normal.flac',
        'mp3_cbr128_44100_stereo.normal.mp3',
        'mp4_h264_aac_320x240.normal.mp4',
        'mkv_vp9_opus_320x240.normal.mkv',
        'webm_vp8_vorbis_320x240.normal.webm',
      ];
      for (final fixture in fixtures) {
        final document = parseFile('test/fixtures/$fixture');
        expect(
          _byKey(document.fileFields, 'file_size')!.value,
          File('test/fixtures/$fixture').lengthSync(),
          reason: fixture,
        );
      }
    });

    test('容器格式按内容判定：WebM 与 Matroska 分得开', () {
      final matroska = parseFile(
        'test/fixtures/mkv_vp9_opus_320x240.normal.mkv',
      );
      expect(
        _byKey(matroska.fileFields, 'container_format')!.value,
        'Matroska',
      );

      final webm = parseFile(
        'test/fixtures/webm_vp8_vorbis_320x240.normal.webm',
      );
      expect(_byKey(webm.fileFields, 'container_format')!.value, 'WebM');
    });

    test('容器格式：MP4 取 ftyp 的 major brand，其它格式取格式名', () {
      final mp4 = parseFile('test/fixtures/mp4_h264_aac_320x240.normal.mp4');
      expect(_byKey(mp4.fileFields, 'container_format')!.value, 'isom');

      final mov = parseFile('test/fixtures/mov_mpeg4_aac_320x240.normal.mov');
      expect(_byKey(mov.fileFields, 'container_format')!.value, 'qt  ');

      final aiff = parseFile(
        'test/fixtures/aiff_pcm_s16be_48000_mono.normal.aiff',
      );
      expect(_byKey(aiff.fileFields, 'container_format')!.value, 'AIFF');

      final flac = parseFile('test/fixtures/flac_s16_44100_stereo.normal.flac');
      expect(_byKey(flac.fileFields, 'container_format')!.value, 'FLAC');

      final mp3 = parseFile('test/fixtures/mp3_cbr128_44100_stereo.normal.mp3');
      expect(_byKey(mp3.fileFields, 'container_format')!.value, 'MP3');
    });

    test('三个中央键只出现一次（Matroska 的提取器也带 file_size / container_format）', () {
      for (final fixture in <String>[
        'wav_pcm_s16le_44100_stereo.normal.wav',
        'aiff_pcm_s16be_48000_mono.normal.aiff',
        'flac_s16_44100_stereo.normal.flac',
        'mp3_cbr128_44100_stereo.normal.mp3',
        'mp4_h264_aac_320x240.normal.mp4',
        'mkv_vp9_opus_320x240.normal.mkv',
      ]) {
        final document = parseFile('test/fixtures/$fixture');
        for (final key in <String>[
          'file_name',
          'file_size',
          'container_format',
        ]) {
          expect(
            document.fileFields.where((field) => field.key == key).length,
            1,
            reason: '$fixture 的 $key',
          );
        }
      }
    });

    test('在 isolate 里解析得到同样的结果', () async {
      final document = await parseFileInIsolate(wavFixture);
      expect(document.detectedFormat, 'WAV');
      expect(document.tracks.length, 1);
    });

    test('按深度重新解析结构树（供结构树惰性展开用）', () {
      final root = parseStructure(mp4Fixture, depth: 3);
      expect(root, isNotNull);
      expect(root!.children.length, greaterThan(0));

      final deeper = parseStructure(mp4Fixture, depth: 8);
      expect(deeper, isNotNull);
    });
  });

  group('预打开文件的注入点', () {
    test('环境变量不存在时返回空列表', () {
      expect(readOpenFilesFromEnvironment(const <String, String>{}), isEmpty);
    });

    test('环境变量按分号切分并去掉空白', () {
      expect(
        readOpenFilesFromEnvironment(const <String, String>{
          kOpenFilesEnvironmentVariable: ' a.wav ; b.mp4 ;; c.flac ',
        }),
        <String>['a.wav', 'b.mp4', 'c.flac'],
      );
    });

    test('环境变量为空字符串时返回空列表', () {
      expect(
        readOpenFilesFromEnvironment(const <String, String>{
          kOpenFilesEnvironmentVariable: '  ;  ',
        }),
        isEmpty,
      );
    });
  });
}
