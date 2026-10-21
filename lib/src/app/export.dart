/// 导出层：把解析结果导出成 JSON，以及把字段值复制到剪贴板。
///
/// 两件事：
///
/// 1. **导出 JSON**——工具条上的「导出 JSON」→ 平台保存对话框 → 写出 JSON。
///    JSON **同时包含语义字段与结构树**（规格 user story 42）：
///    - 语义字段按「文件级 / 轨道级 / 标签」分区，字段用**英文技术名**做 key
///      （user story 43），另附中文显示名 `label`；
///    - 字段的 `origin`（`read` / `derived`）与 `unit` 都保留，不丢信息；
///    - 结构树是递归的节点数组，每个节点含 `type` / `offset` / `size` /
///      `isOpaque` / `fields` / `children`；
///    - `codec` 之类的标识**保持英文原样**，不翻译；
///    - 二进制值（封面图之类的 `Uint8List`）确定性地编码成
///      `{"kind": "binary", "base64": "…"}`，不往 JSON 里吐裸字节。
///
/// 2. **复制字段值**——语义字段视图里右键某个字段 → 复制它的值。
///    值的格式化规则：数值直接用其字符串形式；时长格式化成 `HH:MM:SS.mmm`；
///    带单位的字段复制时**不含单位**（单位在界面上单独显示）。
///
/// **JSON 的键名顺序稳定**（Dart 的 Map 保持插入顺序），所以两次导出可以直接
/// diff。
///
/// 契约见 `docs/design/ui-layout.md` 与 `.scratch/media-info-mvp/issues/
/// 22-export-json-copy.md`。
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/node.dart';
import '../core/tag.dart';
import 'parse_service.dart';

/// 导出 JSON 的 schema 版本。
///
/// 以后 JSON 的形状变了就把这个数加一，方便下游脚本判断。
const int kExportSchemaVersion = 1;

/// 导出 JSON 里标记生成者的键。
const String kExportToolName = 'media_info';

/// 时长字段的 key——这个字段的值复制时格式化成 `HH:MM:SS.mmm`。
const String kDurationFieldKey = 'duration';

/// 构造导出用的 JSON 结构（**纯函数**：输入文档，输出可 JSON 编码的 Map）。
///
/// 键的顺序是固定的（插入顺序），所以两次调用得到同样的 JSON 文本。
Map<String, Object?> buildDocumentJsonMap(ParsedDocument document) {
  return <String, Object?>{
    'tool': kExportToolName,
    'schemaVersion': kExportSchemaVersion,
    'path': document.path,
    'format': document.detectedFormat,
    'truncated': document.truncated,
    'error': document.error,
    'extensionWarning': document.extensionWarning,
    'fileFields': _fieldsMap(document.fileFields),
    'tracks': <Object?>[
      for (final track in document.tracks)
        <String, Object?>{
          'trackIndex': track.trackIndex,
          'fields': _fieldsMap(track.fields),
        },
    ],
    'tags': <Object?>[
      for (final tag in document.tags)
        <String, Object?>{
          'key': tag.key,
          'value': _encodeValue(tag.value),
          'source': tag.source,
        },
    ],
    'structure': document.root == null ? null : _nodeMap(document.root!),
  };
}

/// 构造导出用的 JSON 文本（**纯函数**：输入文档，输出 JSON 字符串）。
///
/// 用缩进输出——可读、可 diff。
String buildDocumentJson(ParsedDocument document) {
  const JsonEncoder encoder = JsonEncoder.withIndent('  ');
  return '${encoder.convert(buildDocumentJsonMap(document))}\n';
}

/// 把文档的 JSON 写到 [path]（UTF-8）。
///
/// 这是「写出文件」这一步的接缝——不碰保存对话框，所以可以直接在测试里断言
/// 写出来的内容。
Future<void> writeDocumentJson(ParsedDocument document, String path) async {
  final file = File(path);
  await file.writeAsString(
    buildDocumentJson(document),
    encoding: utf8,
    flush: true,
  );
}

/// 导出文档为 JSON 文件：弹平台保存对话框 → 写文件。
///
/// - 对话框用平台自带的保存对话框（`file_selector` 的 [getSaveLocation]），
///   不新增依赖；
/// - **用户取消**对话框时直接返回：不写文件，也不提示；
/// - 写失败时用 [messenger]（若给了）提示「导出失败：…」，不抛异常。
///
/// [messenger] 用来在写完后弹一个 SnackBar 说明结果；不传就静默。
Future<void> exportDocumentToJson(
  ParsedDocument document, {
  ScaffoldMessengerState? messenger,
}) async {
  final FileSaveLocation? location;
  try {
    location = await getSaveLocation(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'JSON 文件', extensions: <String>['json']),
      ],
      suggestedName: suggestedJsonFileName(document),
      confirmButtonText: '保存',
    );
  } on Object catch (error) {
    _notify(messenger, '导出失败：$error');
    return;
  }

  // 用户取消了保存对话框：什么都不做。
  if (location == null) return;

  final path = _ensureJsonExtension(location.path);
  try {
    await writeDocumentJson(document, path);
  } on Object catch (error) {
    _notify(messenger, '导出失败：$error');
    return;
  }
  _notify(messenger, '已导出到 $path');
}

/// 导出时默认的文件名（源文件名 + `.json`）。
String suggestedJsonFileName(ParsedDocument document) {
  final name = document.path.replaceAll('\\', '/').split('/').last;
  final base = name.isEmpty ? 'media_info' : name;
  return base.toLowerCase().endsWith('.json') ? base : '$base.json';
}

/// 把字段值格式化成复制到剪贴板的文本（**纯函数**）。
///
/// 规则：
/// - `duration` 字段 → `HH:MM:SS.mmm`；
/// - 数值 → 其字符串形式（整数值不带小数尾巴）；
/// - 字符串 → 原样；若结尾带着 [unit] 则去掉单位；
/// - 布尔 → `true` / `false`；
/// - 二进制（`Uint8List`）→ 十六进制串；
/// - `null` → 空字符串。
String formatCopiedValue(Object? value, {String? key, String? unit}) {
  if (value == null) return '';
  if (key == kDurationFieldKey && value is num) {
    final duration = _formatDuration(value.toDouble());
    if (duration != null) return duration;
  }
  if (value is bool) return value ? 'true' : 'false';
  if (value is int) return value.toString();
  if (value is double) {
    if (!value.isFinite) return value.toString();
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return value.toInt().toString();
    }
    return value.toString();
  }
  if (value is String) return _stripUnit(value, unit);
  if (value is Uint8List) return _toHex(value);
  if (value is List) {
    return value.map((Object? item) => formatCopiedValue(item)).join(', ');
  }
  if (value is Map) {
    return value.entries
        .map(
          (MapEntry<Object?, Object?> entry) =>
              '${entry.key}: ${formatCopiedValue(entry.value)}',
        )
        .join(', ');
  }
  return value.toString();
}

/// 语义字段的复制文本。
String formatCopiedFieldValue(SemanticField field) =>
    formatCopiedValue(field.value, key: field.key, unit: field.unit);

/// 标签值的复制文本。
String formatCopiedTagValue(Tag tag) =>
    formatCopiedValue(tag.value, key: tag.key);

/// 把文本复制到系统剪贴板。
Future<void> copyTextToClipboard(String text) =>
    Clipboard.setData(ClipboardData(text: text));

// ---------------------------------------------------------------------------
// 内部实现
// ---------------------------------------------------------------------------

/// 一组语义字段 → `key → 字段对象` 的映射。
///
/// key 用**英文技术名**；万一同一个作用域里出现重名的 key，第二个起追加
/// `#2` / `#3` 后缀——保证不丢字段，同时顺序稳定。
Map<String, Object?> _fieldsMap(List<SemanticField> fields) {
  final result = <String, Object?>{};
  for (final field in fields) {
    final key = _uniqueKey(result, field.key);
    result[key] = <String, Object?>{
      'label': field.label,
      'value': _encodeValue(field.value),
      'unit': field.unit,
      'origin': field.origin.name,
      'source': field.source,
    };
  }
  return result;
}

/// 结构树的一个节点 → JSON 对象（递归）。
Map<String, Object?> _nodeMap(ContainerNode node) {
  return <String, Object?>{
    'type': node.type,
    'offset': node.offset,
    'size': node.size,
    'dataOffset': node.dataOffset,
    'dataSize': node.dataSize,
    'isOpaque': node.isOpaque,
    'fields': _fieldsMap(node.fields),
    'children': <Object?>[for (final child in node.children) _nodeMap(child)],
  };
}

/// 把字段值编码成可 JSON 编码的值。
///
/// 二进制（`Uint8List`）确定性地编码成 `{"kind": "binary", "base64": "…"}`——
/// 不往 JSON 里吐裸字节，也不丢信息。
Object? _encodeValue(Object? value) {
  if (value == null) return null;
  if (value is Uint8List) {
    return <String, Object?>{'kind': 'binary', 'base64': base64Encode(value)};
  }
  if (value is bool || value is num || value is String) return value;
  if (value is List) {
    return <Object?>[for (final item in value) _encodeValue(item)];
  }
  if (value is Map) {
    return <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in value.entries)
        '${entry.key}': _encodeValue(entry.value),
    };
  }
  return value.toString();
}

/// 在已用过的 key 里找一个没被占用的（重名时加 `#2` / `#3` 后缀）。
String _uniqueKey(Map<String, Object?> used, String key) {
  if (!used.containsKey(key)) return key;
  var index = 2;
  while (used.containsKey('$key#$index')) {
    index++;
  }
  return '$key#$index';
}

/// 秒数 → `HH:MM:SS.mmm`。
///
/// 不是有限数或负数 → 返回 null（调用方退回普通格式）。
String? _formatDuration(double seconds) {
  if (!seconds.isFinite || seconds < 0) return null;
  final totalMilliseconds = (seconds * 1000).round();
  final milliseconds = totalMilliseconds % 1000;
  final totalSeconds = totalMilliseconds ~/ 1000;
  final second = totalSeconds % 60;
  final minute = (totalSeconds ~/ 60) % 60;
  final hour = totalSeconds ~/ 3600;
  return '${_pad(hour, 2)}:${_pad(minute, 2)}:${_pad(second, 2)}.'
      '${_pad(milliseconds, 3)}';
}

/// 左边补零。
String _pad(int value, int width) => value.toString().padLeft(width, '0');

/// 去掉字符串结尾的单位（只认「空格 + 单位」这种写法，避免误伤）。
String _stripUnit(String value, String? unit) {
  final trimmed = unit?.trim() ?? '';
  if (trimmed.isEmpty) return value;
  final suffix = ' $trimmed';
  if (value.length > suffix.length && value.endsWith(suffix)) {
    return value.substring(0, value.length - suffix.length);
  }
  return value;
}

/// 字节 → 小写十六进制串。
String _toHex(Uint8List bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

/// 路径没有扩展名时补上 `.json`；用户自己写了名字就尊重用户的。
String _ensureJsonExtension(String path) {
  if (path.toLowerCase().endsWith('.json')) return path;
  final name = path.split(RegExp(r'[/\\]')).last;
  final dot = name.lastIndexOf('.');
  if (dot <= 0) return '$path.json';
  return path;
}

/// 弹一个 SnackBar（没有 messenger 时什么都不做）。
void _notify(ScaffoldMessengerState? messenger, String message) {
  messenger?.showSnackBar(SnackBar(content: Text(message)));
}
