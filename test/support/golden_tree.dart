/// **golden 树快照**：把结构树序列化成稳定、可 diff 的 JSON。
///
/// 设计约束（`.scratch/media-info-mvp/issues/23-parser-test-harness.md`）：
///
/// - **稳定**：键顺序固定、不含时间戳、不含绝对路径 → 重新生成是逐字节相同的，
///   git diff 只在解析结果真的变了的时候才动；
/// - **可读**：缩进 JSON，人能直接读；
/// - **可 diff**：字节串（`Uint8List`）渲染成十六进制字符串，不塞原始字节。
///
/// 生成器在 `tool/gen_golden.dart`；测试在 `test/harness/golden_snapshot_test.dart`。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:media_info/src/core/node.dart';

import 'format_parsers.dart';

/// golden 快照目录（相对包根目录）。
const String goldenRoot = 'test/golden';

/// 每个节点最多记录的子节点数。
///
/// MP3 的结构树是**帧列表**（一帧一个节点），长文件会有上千个帧节点，
/// 快照会变得不可读也会变得不可 diff，所以按节点截断。
/// 触发截断时节点上会多出 `childrenTruncated` 与 `childrenTotal` 两个键，
/// 快照文件的 `notes` 里也会写明上限。
const int kMaxGoldenChildren = 64;

/// 一个 golden 快照的目标（某个格式的 `.normal` 素材）。
class GoldenTarget {
  /// 记录一个快照目标。
  const GoldenTarget({required this.format, required this.fixture});

  /// 格式名（`WAV` / `MP4` / `MKV`…）。
  final String format;

  /// 素材文件名（相对 `test/fixtures/`）。
  final String fixture;
}

/// 全部 golden 快照目标：每个目标格式的 `.normal` 素材各一份。
final List<GoldenTarget> goldenTargets = <GoldenTarget>[
  GoldenTarget(format: 'WAV', fixture: 'wav_pcm_s16le_44100_stereo.normal.wav'),
  GoldenTarget(
    format: 'AIFF',
    fixture: 'aiff_pcm_s16be_48000_mono.normal.aiff',
  ),
  GoldenTarget(format: 'FLAC', fixture: 'flac_s16_44100_stereo.normal.flac'),
  GoldenTarget(format: 'MP3', fixture: 'mp3_cbr128_44100_stereo.normal.mp3'),
  GoldenTarget(format: 'MP4', fixture: 'mp4_h264_aac_320x240.normal.mp4'),
  GoldenTarget(format: 'MOV', fixture: 'mov_mpeg4_aac_320x240.normal.mov'),
  GoldenTarget(format: 'MKV', fixture: 'mkv_vp9_opus_320x240.normal.mkv'),
  GoldenTarget(format: 'WebM', fixture: 'webm_vp8_vorbis_320x240.normal.webm'),
];

/// golden 文件名（按格式名，如 `mp4.json`）。
String goldenFileName(String format) => '${format.toLowerCase()}.json';

/// golden 文件路径（相对包根目录）。
String goldenPath(String format) => '$goldenRoot/${goldenFileName(format)}';

/// 把字段值渲染成 JSON 里稳定、可读的形式。
///
/// - `Uint8List`（字节串）→ `hex:` 前缀的十六进制字符串；
/// - `List` → 逐项渲染；
/// - `double` 的 NaN / ±Infinity → 字符串（JSON 没有这两种字面量）；
/// - 其它 → 原样。
Object? encodeFieldValue(Object? value) {
  if (value == null) return null;
  if (value is Uint8List) return 'hex:${toHex(value)}';
  if (value is List) {
    return <Object?>[for (final item in value) encodeFieldValue(item)];
  }
  if (value is double) {
    if (value.isNaN) return 'NaN';
    if (value.isInfinite) return value.isNegative ? '-Infinity' : 'Infinity';
    return value;
  }
  if (value is int || value is bool || value is String) return value;
  return value.toString();
}

/// 字节串 → 大写十六进制字符串（不带分隔符）。
String toHex(Uint8List bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
  }
  return buffer.toString();
}

/// 语义字段 → JSON 对象（键 + 值）。
Map<String, Object?> fieldToJson(SemanticField field) => <String, Object?>{
  'key': field.key,
  'value': encodeFieldValue(field.value),
};

/// 结构树节点 → JSON 对象。
///
/// 键顺序固定：类型、偏移、长度、载荷区间、是否不透明、字段、子节点。
/// 子节点超过 [maxChildren] 时截断，并记下 `childrenTruncated` / `childrenTotal`。
Map<String, Object?> nodeToJson(
  ContainerNode node, {
  int maxChildren = kMaxGoldenChildren,
}) {
  final children = node.children;
  final kept = children.length > maxChildren
      ? children.sublist(0, maxChildren)
      : children;
  final truncated = kept.length < children.length;
  return <String, Object?>{
    'type': node.type,
    'offset': node.offset,
    'size': node.size,
    'dataOffset': node.dataOffset,
    'dataSize': node.dataSize,
    'isOpaque': node.isOpaque,
    'fields': <Object?>[for (final field in node.fields) fieldToJson(field)],
    'children': <Object?>[
      for (final child in kept) nodeToJson(child, maxChildren: maxChildren),
    ],
    if (truncated) 'childrenTotal': children.length,
    if (truncated) 'childrenTruncated': true,
  };
}

/// 生成一份 golden 快照的 JSON 结构。
Map<String, Object?> goldenDocument(
  GoldenTarget target, {
  int maxChildren = kMaxGoldenChildren,
}) {
  final result = parseFixtureFile(target.fixture);
  final notes = <String>[
    '本文件由 `dart run tool/gen_golden.dart` 生成，请勿手工编辑。',
    '每个节点最多记录 $maxChildren 个子节点；超出时截断，'
        '并在该节点上标 childrenTruncated / childrenTotal。',
  ];
  if (target.format == 'MP3') {
    final frames = result.root.children
        .where((child) => child.type == 'MPEG Audio Frame')
        .length;
    notes.add(
      'MP3 的结构树是帧列表（一帧一个节点）：本样本共 $frames 帧，'
      '${frames > maxChildren ? '已触发' : '未触发'} $maxChildren 节点上限。',
    );
  }
  return <String, Object?>{
    'format': target.format,
    'fixture': target.fixture,
    'generator': 'tool/gen_golden.dart',
    'notes': notes,
    'tree': nodeToJson(result.root, maxChildren: maxChildren),
  };
}

/// 生成一份 golden 快照的文本（缩进 JSON，末尾带换行）。
String buildGoldenText(
  GoldenTarget target, {
  int maxChildren = kMaxGoldenChildren,
}) {
  final document = goldenDocument(target, maxChildren: maxChildren);
  final encoder = JsonEncoder.withIndent('  ');
  return '${encoder.convert(document)}\n';
}
