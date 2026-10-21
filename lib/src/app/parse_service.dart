/// 解析服务：打开文件 → 嗅探格式 → 解析 → 提取语义字段与标签。
///
/// 解析**在 isolate 里跑**（[parseFileInIsolate]），UI 线程不阻塞。
///
/// 状态模型见 `docs/design/ui-layout.md`；核心契约见 `docs/design/core-api.md`。
library;

import 'dart:io';
import 'dart:isolate';

import '../core/byte_source.dart';
import '../core/errors.dart';
import '../core/node.dart';
import '../core/registry.dart';
import '../core/tag.dart';
import '../formats/all_formats.dart';
import 'extension_check.dart';

/// 默认解析深度。
///
/// 结构树是惰性展开的，但**提取器要看到叶子**才能给出语义字段：
/// MP4 需要 >= 6 层（`moov → trak → mdia → minf → stbl → stsd`），
/// Matroska 需要 >= 5 层。这里取 8，留一点余量。
const int defaultParseDepth = 8;

/// 预打开文件的环境变量名（多个路径用分号 `;` 分隔）。
///
/// 这是**唯一的自动化入口**——文件选择对话框是系统窗口，测不了也点不了。
const String kOpenFilesEnvironmentVariable = 'MEDIA_INFO_OPEN_FILES';

/// 一条轨道的语义字段。
class TrackFields {
  const TrackFields({
    required this.trackIndex,
    this.fields = const <SemanticField>[],
  });

  /// 轨道序号（0 起）。
  final int trackIndex;

  /// 该轨道的语义字段。
  final List<SemanticField> fields;
}

/// 一个打开的文件（一个标签页）的解析结果。
class ParsedDocument {
  const ParsedDocument({
    required this.path,
    this.detectedFormat,
    this.root,
    this.fileFields = const <SemanticField>[],
    this.tracks = const <TrackFields>[],
    this.tags = const <Tag>[],
    this.truncated = false,
    this.error,
    this.extensionWarning,
  });

  /// 文件路径。
  final String path;

  /// 检测到的格式名（如 `WAV` / `MP4` / `Matroska`）；`null` = 无法识别。
  final String? detectedFormat;

  /// 结构树的根节点；无法识别或文件不存在时为 `null`。
  final ContainerNode? root;

  /// 文件级语义字段。
  final List<SemanticField> fileFields;

  /// 轨道级语义字段（按轨道分组）。
  final List<TrackFields> tracks;

  /// 标签（作者写进文件的元数据，与技术属性分开）。
  final List<Tag> tags;

  /// 文件被截断。
  final bool truncated;

  /// 面向用户的中文错误说明（`null` = 没有错误）。
  final String? error;

  /// 扩展名与实际格式不一致的提示（`null` = 没有提示）。
  final String? extensionWarning;
}

/// 解析一个文件（同步）。
///
/// 必须在**已经注册了格式**的 isolate 里调用——应用侧请用 [parseFileInIsolate]，
/// 它会在新 isolate 里先调 [registerAllFormats]（注册表是 isolate 级的全局变量）。
///
/// 引擎不抛异常给 UI 层：截断、读不出来等都以 [ParsedDocument.error] 的形式传达，
/// 已读到的部分结构照常返回。
ParsedDocument parseFile(String path, {int depth = defaultParseDepth}) {
  _ensureFormatsRegistered();
  final file = File(path);
  if (!file.existsSync()) {
    return ParsedDocument(path: path, error: '文件不存在');
  }

  int fileSize = 0;
  try {
    fileSize = file.lengthSync();
  } on FileSystemException {
    fileSize = 0;
  }

  final FileByteSource source;
  try {
    source = FileByteSource.fromPath(path);
  } on FileSystemException {
    return ParsedDocument(path: path, error: '无法打开文件');
  }

  try {
    final spec = detectFormat(source);
    if (spec == null) {
      // 不是媒体文件：不是错误，是"无法识别的文件格式"状态。
      return ParsedDocument(
        path: path,
        fileFields: _fileFields(
          const <SemanticField>[],
          path: path,
          fileSize: fileSize,
          formatName: null,
        ),
      );
    }

    final result = parseFormat(spec, source, depth: depth);
    final extracted =
        spec.extractor?.call(result.root) ?? const <SemanticField>[];

    return ParsedDocument(
      path: path,
      detectedFormat: spec.name,
      root: result.root,
      fileFields: _fileFields(
        extracted,
        path: path,
        fileSize: fileSize,
        formatName: spec.name,
      ),
      tracks: _tracksOf(extracted),
      tags: collectTags(result.root),
      truncated: result.truncated,
      error: result.error,
      extensionWarning: checkExtension(path, spec.name),
    );
  } on TruncatedFile catch (error) {
    return ParsedDocument(
      path: path,
      error: '文件在偏移 ${error.offset} 处截断，还差 ${error.missingBytes} 字节',
    );
  } on FileSystemException catch (error) {
    return ParsedDocument(path: path, error: '读取文件失败：${error.message}');
  } catch (error) {
    return ParsedDocument(path: path, error: '解析失败：$error');
  } finally {
    source.close();
  }
}

/// 在后台 isolate 里解析一个文件。
///
/// 解析在 isolate 里跑，UI 线程不阻塞。新 isolate 里全局注册表是空的，
/// 所以这个 isolate 里会自己注册一遍全部格式。
Future<ParsedDocument> parseFileInIsolate(
  String path, {
  int depth = defaultParseDepth,
}) => Isolate.run(() => _parseInIsolate(path, depth));

ParsedDocument _parseInIsolate(String path, int depth) {
  registerAllFormats();
  return parseFile(path, depth: depth);
}

/// 注册表是 isolate 级的全局变量：新的 isolate 里它是空的。
///
/// 这里只在注册表为空时注册一遍，避免覆盖调用方自己登记的格式。
void _ensureFormatsRegistered() {
  if (allFormats().isEmpty) registerAllFormats();
}

/// 解析一个文件的结构树（同步），不提取语义字段。
///
/// 结构树的惰性展开会用它按更大的深度重新解析（重新读字节，不缓存）。
ContainerNode? parseStructure(String path, {int depth = defaultParseDepth}) {
  _ensureFormatsRegistered();
  final file = File(path);
  if (!file.existsSync()) return null;
  final FileByteSource source;
  try {
    source = FileByteSource.fromPath(path);
  } on FileSystemException {
    return null;
  }
  try {
    final spec = detectFormat(source);
    if (spec == null) return null;
    return parseFormat(spec, source, depth: depth).root;
  } catch (_) {
    return null;
  } finally {
    source.close();
  }
}

/// 在后台 isolate 里按指定深度解析结构树（供结构树惰性展开用）。
Future<ContainerNode?> parseStructureAtDepth(
  String path, {
  required int depth,
}) => Isolate.run(() {
  registerAllFormats();
  return parseStructure(path, depth: depth);
});

/// 读出环境变量里预打开的文件路径（分号分隔，按顺序）。
///
/// 变量不存在或为空 → 空列表（正常空启动）。
List<String> readOpenFilesFromEnvironment([Map<String, String>? environment]) {
  final env = environment ?? Platform.environment;
  final raw = env[kOpenFilesEnvironmentVariable];
  if (raw == null) return const <String>[];
  return raw
      .split(';')
      .map((String path) => path.trim())
      .where((String path) => path.isNotEmpty)
      .toList(growable: false);
}

/// 由解析服务统一补齐的文件级字段的 key。
const Set<String> _centralFileFieldKeys = <String>{
  'file_name',
  'file_size',
  'container_format',
};

/// 组装文件级字段。
///
/// 规则（见 `docs/design/ui-layout.md`「文件级字段的补齐规则」）：
///
/// 1. 先从提取器结果里**移除** `file_name` / `file_size` / `container_format`
///    三个同名键（Matroska 的提取器会带 `file_size` 与 `container_format`，
///    不移除就会重复出现）；
/// 2. 再由解析服务**统一**补上这三个键，每个格式都有、位置也一样：
///    - `file_name` —— 文件名；
///    - `file_size` —— 文件字节长度；
///    - `container_format` —— MP4 取 `ftyp` 的 major brand（`isom` / `qt  ` /
///      `mp42`…），Matroska 取 EBML 的 DocType（`Matroska` / `WebM`），
///      其它格式取格式名（`WAV` / `AIFF` / `FLAC` / `MP3`）。
///
/// `container_format` 的取值直接**取自提取器已经算好的值**（Matroska 的
/// `container_format` 字段、MP4 的 `brand` 字段），这样核心只有一处真相，
/// 应用层不需要再认识 EBML 元素 ID 或 box 布局。
List<SemanticField> _fileFields(
  List<SemanticField> extracted, {
  required String path,
  required int fileSize,
  required String? formatName,
}) {
  final extractedFile = <SemanticField>[
    for (final field in extracted)
      if (field.scope == FieldScope.file) field,
  ];

  // 1. 移除三个中央键的已有字段（Matroska 会带 `file_size` / `container_format`）。
  final kept = <SemanticField>[
    for (final field in extractedFile)
      if (!_centralFileFieldKeys.contains(field.key)) field,
  ];

  // 2. 由解析服务统一补齐。
  final containerFormat = _containerFormatOf(extractedFile, formatName);
  final merged = <SemanticField>[
    SemanticField(
      key: 'file_name',
      label: '文件名',
      value: _fileNameOf(path),
      scope: FieldScope.file,
      source: 'file',
    ),
    SemanticField(
      key: 'file_size',
      label: '文件大小',
      value: fileSize,
      unit: 'byte',
      scope: FieldScope.file,
      source: 'file',
    ),
    if (containerFormat != null)
      SemanticField(
        key: 'container_format',
        label: '容器格式',
        value: containerFormat.value,
        scope: FieldScope.file,
        source: containerFormat.source,
      ),
  ];

  merged.addAll(kept);
  return merged;
}

/// 算 `container_format` 的值与来源。
///
/// - Matroska 的提取器已经给了 `container_format`（EBML 的 DocType 派生名，
///   `Matroska` / `WebM`）——直接用；
/// - MP4 的提取器给了 `brand`（`ftyp` 的 major brand，`isom` / `qt  ` / `mp42`…）
///   ——用它；
/// - 其它格式用格式名（`WAV` / `AIFF` / `FLAC` / `MP3`）。
({Object? value, String? source})? _containerFormatOf(
  List<SemanticField> extractedFile,
  String? formatName,
) {
  SemanticField? brand;
  for (final field in extractedFile) {
    if (field.key == 'container_format') {
      return (value: field.value, source: field.source);
    }
    if (field.key == 'brand') {
      brand ??= field;
    }
  }
  if (brand != null) {
    return (value: brand.value, source: brand.source);
  }
  if (formatName == null) return null;
  return (value: formatName, source: 'detected_format');
}

/// 把轨道级字段按 `trackIndex` 分组（序号升序）。
List<TrackFields> _tracksOf(List<SemanticField> extracted) {
  final grouped = <int, List<SemanticField>>{};
  for (final field in extracted) {
    if (field.scope != FieldScope.track) continue;
    grouped
        .putIfAbsent(field.trackIndex ?? 0, () => <SemanticField>[])
        .add(field);
  }
  final indices = grouped.keys.toList()..sort();
  return <TrackFields>[
    for (final index in indices)
      TrackFields(trackIndex: index, fields: grouped[index]!),
  ];
}

/// 取路径里的文件名（不含目录）。
String _fileNameOf(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  return slash < 0 ? normalized : normalized.substring(slash + 1);
}
