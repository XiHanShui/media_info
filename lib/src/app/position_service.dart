/// 位置索引的应用层入口。
///
/// 核心层只提供"怎么算"，**"读哪个字段算"是格式自己的事**——所以由
/// `FormatSpec.positionIndexBuilder` 提供精确实现，这里负责把时长取出来并组装。
library;

import '../core/node.dart';
import '../core/position_index.dart';
import '../core/registry.dart';
import 'parse_service.dart';

/// 从文件级语义字段里取时长。
Duration? durationOf(List<SemanticField> fileFields) {
  for (final field in fileFields) {
    if (field.key != 'duration') continue;
    final value = field.value;
    if (value is num) {
      return Duration(microseconds: (value * 1000000).round());
    }
  }
  return null;
}

/// 为一个已解析的文件构建位置索引。
///
/// 返回 `null` 表示这个文件无法把字节位置映射到时间（读不出时长，或格式不支持）。
PositionIndex? buildDocumentPositionIndex(
  FormatSpec spec,
  ContainerNode root,
  List<SemanticField> fileFields,
) {
  final duration = durationOf(fileFields);
  if (duration == null || duration <= Duration.zero) return null;
  return buildPositionIndex(
    root: root,
    duration: duration,
    exactBuilder: spec.positionIndexBuilder,
  );
}

/// 按已解析文档的格式查找注册项并构建位置索引。
PositionIndex? positionIndexOf(ParsedDocument document) {
  final root = document.root;
  final format = document.detectedFormat;
  if (root == null || format == null) return null;

  FormatSpec? spec;
  for (final candidate in allFormats()) {
    if (candidate.name == format) {
      spec = candidate;
      break;
    }
  }
  if (spec == null) return null;
  return buildDocumentPositionIndex(spec, root, document.fileFields);
}
