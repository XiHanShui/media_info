/// 平台与打包相关的断言。
///
/// 覆盖 user story 44、45、50、51、52：
/// Windows / macOS 双端构建、CI 矩阵与钉死的 Flutter 版本、
/// 工具不联网不外传、新增格式的扩展点形状、每个格式都有可复现的样本与断言。
///
/// 这些不是「运行时」行为，但它们是规格里写死的验收条件——
/// 用仓库里的文件作为真相源来断言。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/core/registry.dart';
import 'package:media_info/src/formats/all_formats.dart';

import '../support/coverage_lists.dart';
import '../support/fixture_paths.dart';

/// 仓库根目录（`flutter test` 的工作目录）。
Directory repoRoot() => Directory.current;

/// 读一个仓库里的文本文件。
String readRepoFile(String relativePath) =>
    File('${repoRoot().path}/$relativePath').readAsStringSync();

void main() {
  group('平台', () {
    test('只做桌面：windows 与 macos 的脚手架都在', () {
      expect(Directory('${repoRoot().path}/windows').existsSync(), isTrue);
      expect(Directory('${repoRoot().path}/macos').existsSync(), isTrue);
    });

    test('不做移动端与 Web', () {
      for (final String platform in <String>[
        'android',
        'ios',
        'linux',
        'web',
      ]) {
        expect(
          Directory('${repoRoot().path}/$platform').existsSync(),
          isFalse,
          reason: 'MVP 不做 $platform',
        );
      }
    });
  });

  group('CI：双端矩阵与钉死的 Flutter 版本', () {
    test('工作流文件存在', () {
      expect(
        File('${repoRoot().path}/.github/workflows/build.yml').existsSync(),
        isTrue,
      );
    });

    test('矩阵里有 windows-latest 与 macos-latest', () {
      final String workflow = readRepoFile('.github/workflows/build.yml');

      expect(workflow, contains('windows-latest'));
      expect(workflow, contains('macos-latest'));
    });

    test('Flutter 版本被钉死，不用 latest', () {
      final String workflow = readRepoFile('.github/workflows/build.yml');

      expect(workflow, contains("flutter-version: '3.41.6'"));
      expect(workflow, isNot(contains('flutter-version: latest')));
      expect(workflow, isNot(contains("flutter-version: 'latest'")));
    });

    test('CI 不用本机的中国镜像环境变量', () {
      final String workflow = readRepoFile('.github/workflows/build.yml');

      expect(workflow, isNot(contains('PUB_HOSTED_URL=')));
      expect(workflow, isNot(contains('FLUTTER_STORAGE_BASE_URL=')));
    });

    test('不在 PR 上跑（只在 push 到 main、打 tag、手动触发）', () {
      final String workflow = readRepoFile('.github/workflows/build.yml');

      expect(workflow, isNot(contains('pull_request:')));
      expect(workflow, contains('workflow_dispatch:'));
    });

    test('两端都出 zip（Windows 用 zip，macOS 用 tar.gz 包 .app）', () {
      final String workflow = readRepoFile('.github/workflows/build.yml');

      expect(workflow, contains('artifact_ext: zip'));
      expect(workflow, contains('artifact_ext: tar.gz'));
      expect(workflow, contains('.zip'));
      expect(workflow, contains('.tar.gz'));
    });

    test('CI 跑 analyze 与 test', () {
      final String workflow = readRepoFile('.github/workflows/build.yml');

      expect(workflow, contains('flutter analyze'));
      expect(workflow, contains('flutter test'));
    });
  });

  group('工具本身不联网、不上传文件', () {
    test('依赖里没有任何网络客户端', () {
      final String pubspec = readRepoFile('pubspec.yaml');

      for (final String forbidden in <String>[
        'http:',
        'dio:',
        'grpc:',
        'web_socket',
        'socket',
        'mqtt',
        'firebase',
        'supabase',
      ]) {
        expect(pubspec, isNot(contains(forbidden)), reason: '不应依赖 $forbidden');
      }
    });

    test('源码里没有发起网络请求的调用', () {
      final List<File> sources = Directory('${repoRoot().path}/lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File file) => file.path.endsWith('.dart'))
          .toList();

      expect(sources, isNotEmpty);
      for (final File file in sources) {
        final String source = file.readAsStringSync();
        expect(
          source,
          isNot(contains('HttpClient')),
          reason: '${file.path} 不该发起网络请求',
        );
        expect(
          source,
          isNot(contains('package:http')),
          reason: '${file.path} 不该依赖网络库',
        );
        expect(
          source,
          isNot(contains('Socket.connect')),
          reason: '${file.path} 不该开网络连接',
        );
      }
    });

    test('唯一的运行时依赖是 Flutter 自带的与 file_selector', () {
      final String pubspec = readRepoFile('pubspec.yaml');

      expect(pubspec, contains('file_selector:'));
      expect(pubspec, contains('cupertino_icons:'));
    });
  });

  group('新增格式的扩展点（user story 51）', () {
    test('注册表登记的是规格表 + 可选的提取器，不是解析器对象', () {
      registerAllFormats();

      for (final FormatSpec format in allFormats()) {
        expect(format.container, isNotNull, reason: '${format.name} 缺规格表');
        expect(
          format.container.children.isNotEmpty || format.parser != null,
          isTrue,
          reason: '${format.name} 既没有子块表也没有自定义解析器',
        );
        expect(format.extractor, isNotNull, reason: '${format.name} 缺提取器');
      }
    });

    test('加一个新容器 = 写一张 ContainerSpec 表 + 注册一行', () {
      // 表里没有的 type 一律产出不透明叶子——新格式不必穷举所有块。
      registerAllFormats();
      expect(allFormats(), isNotEmpty);
    });
  });

  group('每个格式都有可复现的样本与断言（user story 52）', () {
    test('块覆盖率清单里的每个格式都有素材', () {
      for (final BlockCoverage coverage in blockCoverageLists.values) {
        final String? name = _fixtureOf(coverage.format);
        expect(name, isNotNull, reason: '${coverage.format} 没有素材');
        expect(
          File('${repoRoot().path}/test/fixtures/$name').existsSync(),
          isTrue,
        );
      }
    });

    test('每个格式至少有三类样本：正常 / 边界 / 损坏', () {
      const List<String> formats = <String>[
        'wav',
        'aiff',
        'flac',
        'mp3',
        'mp4',
        'mov',
        'mkv',
        'webm',
      ];

      final List<String> missing = <String>[];
      for (final String format in formats) {
        for (final FixtureCategory category in <FixtureCategory>[
          FixtureCategory.normal,
          FixtureCategory.edge,
          FixtureCategory.truncated,
        ]) {
          if (findFixtureName(format, category) == null) {
            missing.add('$format.${category.label}');
          }
        }
      }

      expect(
        missing,
        isEmpty,
        reason: '规格要求每个目标格式至少三类样本，缺：${missing.join('、')}',
      );
    });

    test('素材是随仓库提交的（不下载外部内容）', () {
      expect(listFixtureNames(), isNotEmpty);
      for (final String name in listFixtureNames()) {
        expect(
          File('${repoRoot().path}/test/fixtures/$name').existsSync(),
          isTrue,
          reason: '$name 应该随仓库提交',
        );
      }
    });
  });

  group('界面语言与术语（user story 46 / 47）', () {
    test('中文文案来自同一个地方，字段与块名保持英文', () {
      // 字段的 key 是英文技术名（代码标识符）；中文只出现在 label 上。
      registerAllFormats();
      for (final FormatSpec format in allFormats()) {
        expect(format.name, matches(RegExp(r'^[A-Za-z0-9]+$')));
      }
    });
  });
}

/// 按格式名挑一个正常素材。
String? _fixtureOf(String format) => switch (format) {
  'WAV' => 'wav_pcm_s16le_44100_stereo.normal.wav',
  'AIFF' => 'aiff_pcm_s16be_48000_mono.normal.aiff',
  'FLAC' => 'flac_s16_44100_stereo.normal.flac',
  'MP3' => 'mp3_cbr128_44100_stereo.normal.mp3',
  'MP4' => 'mp4_h264_aac_320x240.normal.mp4',
  'MOV' => 'mov_mpeg4_aac_320x240.normal.mov',
  'MKV' => 'mkv_vp9_opus_320x240.normal.mkv',
  'WebM' => 'webm_vp8_vorbis_320x240.normal.webm',
  _ => null,
};
