/// 位置索引：文件里的**字节位置** ↔ 播放**时间**。
///
/// 这是"播放到解析的位置"的核心：用户在结构树里选中一个块，我们知道它的字节偏移，
/// 但播放器要的是时间戳。中间缺的就是这一层映射。
///
/// 精度分两档：
///
/// - **精确**：字节位置能直接换算成时间。WAV / AIFF（按字节率）、MP3（按帧表）做得到。
/// - **估算**：只知道媒体载荷在文件里的范围与总时长，就按比例线性换算。
///   对恒定帧率（CFR）的媒体是准的；可变帧率（VFR）会有偏差——所以界面要说明是估算。
///
/// 换不来就返回 `null`，不要猜。
///
/// 格式特有的知识（字段名、块结构）**不放这里**——由各格式模块通过
/// `FormatSpec.positionIndexBuilder` 提供自己的构建器；这里只放通用的骨架与兜底估算。
library;

import 'node.dart';

/// 文件里的一段字节范围。
class ByteRange {
  const ByteRange(this.start, this.end);

  /// 起始偏移（含）。
  final int start;

  /// 结束偏移（不含）。
  final int end;

  /// 长度（字节）。
  int get length => end - start;

  @override
  String toString() => 'ByteRange($start, $end)';
}

/// 字节位置 ↔ 播放时间的映射。
class PositionIndex {
  const PositionIndex({
    required this.duration,
    this.payload,
    this.exactMapper,
    this.exactInverse,
  });

  /// 媒体总时长。
  final Duration duration;

  /// 媒体载荷在文件里的范围（用于线性估算）。
  final ByteRange? payload;

  /// 精确的 字节偏移 → 时间。
  final Duration? Function(int offset)? exactMapper;

  /// 精确的 时间 → 字节偏移。
  final int? Function(Duration position)? exactInverse;

  /// 映射是否精确（false = 按比例估算）。
  bool get isExact => exactMapper != null;

  /// 字节偏移 → 播放位置。无法确定时返回 `null`。
  Duration? timestampOf(int offset) {
    final exact = exactMapper;
    if (exact != null) {
      final value = exact(offset);
      if (value != null) return value;
    }
    final range = payload;
    if (range == null || range.length <= 0) return null;
    if (offset < range.start || offset >= range.end) return null;
    final ratio = (offset - range.start) / range.length;
    return Duration(
      microseconds: (duration.inMicroseconds * ratio).round(),
    );
  }

  /// 播放位置 → 字节偏移。无法确定时返回 `null`。
  int? offsetOf(Duration position) {
    final exact = exactInverse;
    if (exact != null) {
      final value = exact(position);
      if (value != null) return value;
    }
    final range = payload;
    if (range == null || range.length <= 0) return null;
    if (position < Duration.zero || position > duration) return null;
    if (duration.inMicroseconds <= 0) return null;
    final ratio = position.inMicroseconds / duration.inMicroseconds;
    return range.start + (range.length * ratio).round();
  }
}

/// 构建位置索引。
///
/// [exactBuilder] 是格式自带的精确构建器；没有就用 [estimatedPositionIndex] 兜底。
PositionIndex? buildPositionIndex({
  required ContainerNode root,
  required Duration duration,
  PositionIndex? Function(ContainerNode root, Duration duration)? exactBuilder,
}) {
  if (duration <= Duration.zero) return null;
  final exact = exactBuilder?.call(root, duration);
  if (exact != null) return exact;
  return estimatedPositionIndex(root, duration);
}

/// 兜底的**线性估算**：按媒体载荷区间与总时长按比例换算。
///
/// 媒体载荷的位置：
/// - MP4 / MOV：`mdat` 盒
/// - FLAC：最后一个元数据块之后（音频帧）
///
/// Matroska 的 `Cluster` 在树里是十六进制元素 ID，属于格式知识，
/// 由 `lib/src/formats/matroska.dart` 自己提供构建器。
PositionIndex? estimatedPositionIndex(ContainerNode root, Duration duration) {
  if (duration <= Duration.zero) return null;

  ByteRange? payload;

  final mdat = findNode(root, 'mdat');
  if (mdat != null) {
    payload = ByteRange(mdat.dataOffset, mdat.dataOffset + mdat.dataSize);
  }

  payload ??= _tailPayload(root);

  if (payload == null || payload.length <= 0) return null;
  return PositionIndex(duration: duration, payload: payload);
}

/// FLAC：音频帧在最后一个元数据块之后。
ByteRange? _tailPayload(ContainerNode root) {
  if (root.children.isEmpty) return null;
  var last = 0;
  for (final child in root.children) {
    final end = child.offset + child.size;
    if (end > last) last = end;
  }
  if (last <= 0 || last >= root.size) return null;
  return ByteRange(last, root.size);
}

/// 在树里找第一个类型为 [type] 的节点。
ContainerNode? findNode(ContainerNode root, String type) {
  for (final child in root.children) {
    if (child.type == type) return child;
    final found = findNode(child, type);
    if (found != null) return found;
  }
  return null;
}

/// 收集树里所有类型为 [type] 的节点。
List<ContainerNode> findNodes(ContainerNode root, String type) {
  final result = <ContainerNode>[];
  void walk(ContainerNode node) {
    for (final child in node.children) {
      if (child.type == type) result.add(child);
      walk(child);
    }
  }

  walk(root);
  return result;
}

/// 节点的某个字段值（按 key 找）。
Object? fieldOf(ContainerNode node, String key) {
  for (final field in node.fields) {
    if (field.key == key) return field.value;
  }
  return null;
}
