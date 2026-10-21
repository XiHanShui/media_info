/// 测试素材的定位 helper。
///
/// 素材命名约定：`<格式>_<参数>.<类别>.<扩展名>`，类别取
/// `normal` / `edge` / `truncated` / `liesize` 四种之一
/// （见 `.scratch/media-info-mvp/issues/04-test-fixtures.md`）。
///
/// 损坏素材多一段：`<格式>_<参数>.normal.<类别>.<扩展名>`——它们是正常素材的
/// 损坏版本（截断 / 长度字段撒谎），所以「基名」里还留着 `normal` 那一段。
/// 本模块按「最后一段是扩展名、倒数第二段是类别」来解析，两种写法都能吃下。
///
/// ```dart
/// final source = fixtureSource('wav_pcm_s16le_44100_stereo.normal.wav');
/// addTearDown(source.close);
/// ```
library;

import 'dart:io';

import 'package:media_info/src/core/byte_source.dart';

/// 素材目录（相对包根目录；`flutter test` 的工作目录就是包根目录）。
const String fixtureRoot = 'test/fixtures';

/// 素材类别。
enum FixtureCategory {
  /// 正常样本：最常见的参数组合。
  normal('normal'),

  /// 边界样本：罕见但合法的参数组合。
  edge('edge'),

  /// 截断样本：文件被砍断，声明长度大于实际内容。
  truncated('truncated'),

  /// 长度字段撒谎的样本：块头声明的长度超出文件实际剩余。
  liesize('liesize');

  const FixtureCategory(this.label);

  /// 文件名里出现的类别片段。
  final String label;

  /// 从文件名里的类别片段解析出类别。
  ///
  /// 片段不认识时抛 [FormatException]。
  static FixtureCategory parse(String label) {
    for (final category in FixtureCategory.values) {
      if (category.label == label) return category;
    }
    throw FormatException(
      '未知的素材类别：$label（合法取值：'
      '${FixtureCategory.values.map((c) => c.label).join(' / ')}）',
    );
  }
}

/// 素材文件名的解析结果。
class FixtureName {
  /// 按 `test/fixtures/` 下的文件名构造。
  ///
  /// 文件名必须形如 `<格式>_<参数>.<类别>.<扩展名>`（损坏素材多一段 `.normal`）。
  factory FixtureName(String fileName) {
    final parts = fileName.split('.');
    if (parts.length < 3) {
      throw FormatException('素材文件名不符合 `<格式>_<参数>.<类别>.<扩展名>` 约定：$fileName');
    }
    final extension = parts.last;
    final category = FixtureCategory.parse(parts[parts.length - 2]);
    final baseName = parts.sublist(0, parts.length - 2).join('.');
    if (baseName.isEmpty) {
      throw FormatException('素材文件名缺少格式与参数段：$fileName');
    }
    final format = baseName.split('_').first;
    final rest = baseName.substring(format.length + 1);
    // 损坏素材的基名尾部多一段 `normal`（它是正常素材的损坏版本）。
    final params = rest.endsWith('.normal')
        ? rest.substring(0, rest.length - '.normal'.length)
        : rest;
    return FixtureName._(
      fileName: fileName,
      extension: extension,
      category: category,
      baseName: baseName,
      format: format,
      params: params,
    );
  }

  const FixtureName._({
    required this.fileName,
    required this.extension,
    required this.category,
    required this.baseName,
    required this.format,
    required this.params,
  });

  /// 文件名（不含目录）。
  final String fileName;

  /// 扩展名（不含点），如 `wav`。
  final String extension;

  /// 类别。
  final FixtureCategory category;

  /// 基名：去掉类别与扩展名之后剩下的部分，如 `wav_pcm_s16le_44100_stereo.normal`。
  final String baseName;

  /// 格式键：基名的第一段，如 `wav`、`mp4`、`mkv`。
  final String format;

  /// 参数段：基名去掉格式键之后的部分，如 `pcm_s16le_44100_stereo`。
  final String params;

  @override
  String toString() => fileName;
}

/// 解析素材文件名。
FixtureName parseFixtureName(String fileName) => FixtureName(fileName);

/// 素材在仓库里的相对路径（如 `test/fixtures/xxx.wav`）。
///
/// 文件不存在时抛 [StateError]，并把目录下现有的素材列出来——
///
/// 避免「拼错文件名」在测试里变成一个看不懂的失败。
String fixturePath(String fileName) {
  final path = '$fixtureRoot/$fileName';
  if (!File(path).existsSync()) {
    throw StateError(
      '素材不存在：$path\n'
      '现有素材：\n${listFixtureNames().map((n) => '  $n').join('\n')}',
    );
  }
  return path;
}

/// 素材对应的 [File]。
File fixtureFile(String fileName) => File(fixturePath(fileName));

/// 打开素材为字节源。
///
/// 返回的 [FileByteSource] 持有文件句柄，**调用方负责 `close()`**
/// （测试里用 `addTearDown(source.close)`）。
FileByteSource fixtureSource(String fileName) =>
    FileByteSource.fromPath(fixturePath(fileName));

/// `test/fixtures/` 下的全部素材文件名（已排序）。
List<String> listFixtureNames() {
  final dir = Directory(fixtureRoot);
  if (!dir.existsSync()) return const <String>[];
  final names =
      dir
          .listSync()
          .whereType<File>()
          .map((f) => f.path.split(RegExp(r'[/\\]')).last)
          .toList()
        ..sort();
  return names;
}

/// 按格式键与类别找素材文件名；找不到返回 null。
///
/// 格式键见 [FixtureName.format]（`wav` / `aiff` / `flac` / `mp3` /
/// `mp4` / `mov` / `mkv` / `webm`）。
String? findFixtureName(String format, FixtureCategory category) {
  for (final name in listFixtureNames()) {
    final parsed = parseFixtureName(name);
    if (parsed.format == format && parsed.category == category) return name;
  }
  return null;
}

/// 按格式键与类别找素材文件名；找不到抛 [StateError]。
String requireFixtureName(String format, FixtureCategory category) {
  final name = findFixtureName(format, category);
  if (name == null) {
    throw StateError(
      '没有 $format 的 ${category.label} 素材；'
      '现有素材：\n${listFixtureNames().map((n) => '  $n').join('\n')}',
    );
  }
  return name;
}

/// 按格式键与类别取素材路径；找不到抛 [StateError]。
String requireFixturePath(String format, FixtureCategory category) =>
    fixturePath(requireFixtureName(format, category));
