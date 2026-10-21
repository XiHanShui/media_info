/// 解析服务（打开文件 → 嗅探 → 解析 → 提取）的契约断言。
///
/// 覆盖 user story 7、9、39、49、53 的服务层行为：
/// 文件级字段的统一补齐、轨道分组、错误与缺席的字段、
/// 嗅探优先于扩展名、后台 isolate 解析。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/app/parse_service.dart';
import 'package:media_info/src/core/node.dart';

import '../support/fixture_paths.dart';

/// 写一个临时文件，返回路径。
String writeTempFile(String name, List<int> bytes) {
  final Directory dir = Directory.systemTemp.createTempSync(
    'media_info_service',
  );
  addTearDown(() => dir.deleteSync(recursive: true));
  final File file = File('${dir.path}/$name');
  file.writeAsBytesSync(bytes);
  return file.path;
}

/// 字段表（key → 值）。
Map<String, Object?> valuesOf(List<SemanticField> fields) => <String, Object?>{
  for (final SemanticField field in fields) field.key: field.value,
};

void main() {
  group('文件级字段的统一补齐', () {
    test('file_name 取路径里的文件名（不含目录）', () {
      final ParsedDocument doc = parseFile(
        fixturePath('mp4_h264_aac_320x240.normal.mp4'),
      );

      expect(
        valuesOf(doc.fileFields)['file_name'],
        'mp4_h264_aac_320x240.normal.mp4',
      );
    });

    test('file_size 是文件的真实字节数', () {
      final ParsedDocument doc = parseFile(
        fixturePath('mp4_h264_aac_320x240.normal.mp4'),
      );

      expect(valuesOf(doc.fileFields)['file_size'], 11658);
    });

    test('三个中央键排在所有格式特有字段之前', () {
      final ParsedDocument doc = parseFile(
        fixturePath('mp4_h264_aac_320x240.normal.mp4'),
      );

      final List<String> keys = doc.fileFields
          .map((SemanticField f) => f.key)
          .toList();
      expect(keys.take(3), <String>[
        'file_name',
        'file_size',
        'container_format',
      ]);
      expect(keys.indexOf('brand'), greaterThan(2));
    });

    test('Matroska 的 file_size 不会重复出现', () {
      final ParsedDocument doc = parseFile(
        fixturePath('mkv_vp9_opus_320x240.normal.mkv'),
      );

      final List<SemanticField> sizes = doc.fileFields
          .where((SemanticField f) => f.key == 'file_size')
          .toList();
      expect(sizes, hasLength(1));
    });

    test('Matroska 的 container_format 用提取器算出的 DocType', () {
      final ParsedDocument doc = parseFile(
        fixturePath('mkv_vp9_opus_320x240.normal.mkv'),
      );

      final SemanticField format = doc.fileFields.firstWhere(
        (SemanticField f) => f.key == 'container_format',
      );
      expect(format.value, 'matroska');
      expect(format.source, 'EBML/DocType');
    });

    test('无法识别的文件：没有 container_format（不是猜一个）', () {
      final String path = writeTempFile('random.bin', <int>[
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
      ]);

      final ParsedDocument doc = parseFile(path);

      expect(doc.detectedFormat, isNull);
      expect(doc.error, isNull, reason: '识别不出不是错误');
      expect(doc.root, isNull);
      final List<String> keys = doc.fileFields
          .map((SemanticField f) => f.key)
          .toList();
      expect(keys, <String>['file_name', 'file_size']);
      expect(keys, isNot(contains('container_format')));
    });
  });

  group('轨道分组', () {
    test('轨道按 trackIndex 升序分组', () {
      final ParsedDocument doc = parseFile(
        fixturePath('mp4_h264_aac_320x240.normal.mp4'),
      );

      expect(doc.tracks.map((TrackFields t) => t.trackIndex), <int>[0, 1]);
    });

    test('没有 trackIndex 的轨道级字段归到 0 号轨道', () {
      final ParsedDocument doc = parseFile(
        fixturePath('wav_pcm_s16le_44100_stereo.normal.wav'),
      );

      expect(doc.tracks, hasLength(1));
      expect(doc.tracks.single.trackIndex, 0);
      for (final SemanticField field in doc.tracks.single.fields) {
        expect(field.scope, FieldScope.track);
        expect(field.trackIndex, 0);
      }
    });
  });

  group('错误与缺席', () {
    test('文件不存在：错误说明是「文件不存在」', () {
      final ParsedDocument doc = parseFile('test/fixtures/not_here.mp4');

      expect(doc.detectedFormat, isNull);
      expect(doc.error, '文件不存在');
      expect(doc.root, isNull);
      expect(doc.truncated, isFalse);
    });

    test('截断的文件：truncated 为真，且给出中文说明', () {
      final ParsedDocument doc = parseFile(
        fixturePath('mp4_h264_aac_320x240.normal.truncated.mp4'),
      );

      expect(doc.truncated, isTrue);
      expect(doc.error, isNotNull);
      expect(doc.error, contains('截断'));
      expect(doc.root, isNotNull, reason: '已读到的部分结构仍然返回');
    });

    test('正常的文件：没有错误也没有截断', () {
      final ParsedDocument doc = parseFile(
        fixturePath('mp4_h264_aac_320x240.normal.mp4'),
      );

      expect(doc.truncated, isFalse);
      expect(doc.error, isNull);
      expect(doc.extensionWarning, isNull);
    });
  });

  group('按内容判定格式（不看扩展名）', () {
    test('把 WAV 的字节改名成 .mp4，仍然被认成 WAV', () {
      final List<int> bytes = File(
        fixturePath('wav_pcm_s16le_44100_stereo.normal.wav'),
      ).readAsBytesSync();
      final String path = writeTempFile('actually_wav.mp4', bytes);

      final ParsedDocument doc = parseFile(path);

      expect(doc.detectedFormat, 'WAV');
      expect(valuesOf(doc.fileFields)['container_format'], 'WAV');
    });

    test('把 MP4 的字节改名成 .wav，仍然被认成 MP4', () {
      final List<int> bytes = File(
        fixturePath('mp4_h264_aac_320x240.normal.mp4'),
      ).readAsBytesSync();
      final String path = writeTempFile('actually_mp4.wav', bytes);

      final ParsedDocument doc = parseFile(path);

      expect(doc.detectedFormat, 'MP4');
      expect(valuesOf(doc.fileFields)['container_format'], 'isom');
    });
  });

  group('解析深度', () {
    test('depth 1 只建第一层子块', () {
      final ParsedDocument doc = parseFile(
        fixturePath('mp4_h264_aac_320x240.normal.mp4'),
        depth: 1,
      );

      expect(doc.root, isNotNull);
      expect(doc.root!.children, isNotEmpty);
      for (final ContainerNode child in doc.root!.children) {
        expect(child.children, isEmpty);
      }
    });

    test('默认深度能建到轨道层', () {
      final ParsedDocument doc = parseFile(
        fixturePath('mp4_h264_aac_320x240.normal.mp4'),
      );

      final ContainerNode moov = doc.root!.children.firstWhere(
        (ContainerNode c) => c.type == 'moov',
      );
      expect(
        moov.children.where((ContainerNode c) => c.type == 'trak'),
        isNotEmpty,
      );
    });

    test('parseStructure 只返回结构树，不提取字段', () {
      final ContainerNode? root = parseStructure(
        fixturePath('mp4_h264_aac_320x240.normal.mp4'),
      );

      expect(root, isNotNull);
      expect(root!.type, 'MP4');
    });

    test('parseStructure 对不存在的文件返回 null', () {
      expect(parseStructure('test/fixtures/not_here.mp4'), isNull);
    });

    test('parseStructureAtDepth 在新 isolate 里注册格式并按更大深度解析', () async {
      final ContainerNode? root = await parseStructureAtDepth(
        fixturePath('mp4_h264_aac_320x240.normal.mp4'),
        depth: 2,
      );

      expect(root, isNotNull);
      expect(root!.type, 'MP4');
    });
  });

  group('后台 isolate 解析', () {
    test('parseFileInIsolate 在新 isolate 里也能注册格式并完成解析', () async {
      final ParsedDocument doc = await parseFileInIsolate(
        fixturePath('wav_pcm_s16le_44100_stereo.normal.wav'),
      );

      expect(doc.detectedFormat, 'WAV');
      expect(valuesOf(doc.fileFields)['container_format'], 'WAV');
      expect(doc.tracks, hasLength(1));
    });

    test('后台解析对不存在的文件返回错误而不是抛异常', () async {
      final ParsedDocument doc = await parseFileInIsolate(
        'test/fixtures/not_here.mp4',
      );

      expect(doc.error, '文件不存在');
    });
  });

  group('MEDIA_INFO_OPEN_FILES 环境变量', () {
    test('变量不存在时返回空列表', () {
      expect(readOpenFilesFromEnvironment(<String, String>{}), isEmpty);
    });

    test('变量为空时返回空列表', () {
      expect(
        readOpenFilesFromEnvironment(<String, String>{
          kOpenFilesEnvironmentVariable: '',
        }),
        isEmpty,
      );
    });

    test('按分号分隔，顺序保持', () {
      expect(
        readOpenFilesFromEnvironment(<String, String>{
          kOpenFilesEnvironmentVariable: 'a.mp4;b.mp4',
        }),
        <String>['a.mp4', 'b.mp4'],
      );
    });

    test('去掉首尾空白，跳过空段', () {
      expect(
        readOpenFilesFromEnvironment(<String, String>{
          kOpenFilesEnvironmentVariable: ' a.mp4 ; ;b.mp4 ',
        }),
        <String>['a.mp4', 'b.mp4'],
      );
    });

    test('环境变量名固定', () {
      expect(kOpenFilesEnvironmentVariable, 'MEDIA_INFO_OPEN_FILES');
    });
  });
}
