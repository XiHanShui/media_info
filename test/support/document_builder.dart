/// 造「解析结果」的测试辅助函数。
///
/// 解析器级测试用真实素材（`test/support/fixture_paths.dart`），
/// 但**界面级**测试需要可控的输入：字段值、轨道、标签、空区段、
/// 超长字符串、非 ASCII 文本…… 都在这里造。
///
/// 这里造的东西都走**公开构造函数**（`SemanticField` / `ContainerNode` /
/// `Tag` / `ParsedDocument`），不碰任何内部实现。
library;

import 'package:media_info/src/app/parse_service.dart';
import 'package:media_info/src/core/node.dart';
import 'package:media_info/src/core/tag.dart';

/// 造一个结构树节点。
///
/// 默认坐标自洽：`dataOffset == offset`、`dataSize == size`
/// （即「载荷就是整个块」，没有块头）——界面测试不关心块头。
ContainerNode buildNode(
  String type,
  int offset,
  int size, {
  int? dataOffset,
  int? dataSize,
  bool isOpaque = false,
  List<ContainerNode> children = const <ContainerNode>[],
  List<SemanticField> fields = const <SemanticField>[],
}) => ContainerNode(
  type: type,
  offset: offset,
  size: size,
  dataOffset: dataOffset ?? offset,
  dataSize: dataSize ?? size,
  isOpaque: isOpaque,
  children: children,
  fields: fields,
);

/// 造一个语义字段。
///
/// [label] 省略时用 [key] 当显示名（测试里显示名与英文技术名一致最省事）。
SemanticField buildField(
  String key, {
  String? label,
  Object? value,
  String? unit,
  FieldOrigin origin = FieldOrigin.read,
  FieldScope scope = FieldScope.file,
  int? trackIndex,
  String? source,
}) => SemanticField(
  key: key,
  label: label ?? key,
  value: value,
  unit: unit,
  origin: origin,
  scope: scope,
  trackIndex: trackIndex,
  source: source,
);

/// 造一个标签。
Tag buildTag(String key, Object? value, {String? source}) =>
    Tag(key: key, value: value, source: source);

/// 造一个解析后的文档（一个标签页）。
ParsedDocument buildDocument({
  String path = 'demo.mp4',
  String? detectedFormat = 'MP4',
  ContainerNode? root,
  List<SemanticField> fileFields = const <SemanticField>[],
  List<TrackFields> tracks = const <TrackFields>[],
  List<Tag> tags = const <Tag>[],
  bool truncated = false,
  String? error,
  String? extensionWarning,
}) => ParsedDocument(
  path: path,
  detectedFormat: detectedFormat,
  root: root,
  fileFields: fileFields,
  tracks: tracks,
  tags: tags,
  truncated: truncated,
  error: error,
  extensionWarning: extensionWarning,
);

/// 造一组轨道级字段。
TrackFields buildTrack(int trackIndex, List<SemanticField> fields) =>
    TrackFields(trackIndex: trackIndex, fields: fields);
