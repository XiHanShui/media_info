/// 节点模型：结构树节点 + 语义字段。
///
/// 术语依 `GLOSSARY.md`：
/// - 块 (Chunk)：容器结构树里的一个节点。
/// - 语义字段 (Semantic Field)：从容器结构解读出的技术属性。
///
/// 硬约束：节点**不持有字节内容**，只持有 `offset`/`size`，hex 视图按需从文件读。
library;

/// 字段来源：文件里直接写的 / 我们推算的。
enum FieldOrigin {
  /// 值直接来自文件内容。
  read,

  /// 值由其它字段推算而来。
  derived,
}

/// 字段作用域：文件级 / 轨道级。
enum FieldScope {
  /// 文件级属性。
  file,

  /// 轨道级属性。
  track,
}

/// 语义字段 = 从容器结构解读出的技术属性。
class SemanticField {
  const SemanticField({
    required this.key, // 英文技术名，如 'sample_rate'——代码标识符，与规范逐字对照
    required this.label, // 中文显示名，如 '采样率'
    this.value,
    this.unit, // 'Hz'、'bit'、'px'…
    this.origin = FieldOrigin.read,
    this.scope = FieldScope.file,
    this.trackIndex, // scope == FieldScope.track 时有效
    this.source, // 来自哪个块的哪个字段，如 'fmt ' / 'STREAMINFO'
    this.byteRange, // 这个值覆盖的字节范围（读出来的字段才有）
  });

  /// 英文技术名，代码标识符，与格式规范逐字对照。
  final String key;

  /// 中文显示名。
  final String label;

  /// 字段值。
  final Object? value;

  /// 单位，如 'Hz'、'bit'、'px'。
  final String? unit;

  /// 值的来源。
  final FieldOrigin origin;

  /// 作用域。
  final FieldScope scope;

  /// 轨道序号，scope == [FieldScope.track] 时有效。
  final int? trackIndex;

  /// 来自哪个块的哪个字段，如 'fmt ' / 'STREAMINFO'。
  final String? source;

  /// 这个值在文件里覆盖的**字节范围**。
  ///
  /// 只有从字节流里直接读出来的字段才有——手写提取器算出来的值
  /// （比如由多个字节推导出的时长）没有唯一的字节范围，就不标。
  ///
  /// 有了它就能把 hex 视图与字段值对应起来：选中一个字段，
  /// 就能看出它是从哪几个字节来的。
  final ByteRange? byteRange;

  @override
  String toString() => 'SemanticField($key: $value)';
}

/// 文件里的一段字节范围。
class ByteRange {
  const ByteRange(this.start, this.end);

  /// 起始偏移（含）。
  final int start;

  /// 结束偏移（不含）。
  final int end;

  /// 长度（字节）。
  int get length => end - start;

  /// 这个范围是否包含 [offset]。
  bool contains(int offset) => offset >= start && offset < end;

  @override
  String toString() => 'ByteRange($start, $end)';
}

/// 节点里某个字段的字节范围。
///
/// 提取器读出值之后，用它把"这个值是从哪几个字节来的"一起挂到语义字段上。
/// 字段名对不上、或节点本身没有，就返回 `null`——不猜。
ByteRange? byteRangeOf(ContainerNode? node, String fieldName) {
  if (node == null) return null;
  for (final field in node.fields) {
    if (field.key == fieldName) return field.byteRange;
  }
  return null;
}

/// 结构树节点 = 容器里的一个块。
class ContainerNode {
  const ContainerNode({
    required this.type, // 文件里字面的块类型名，如 'moov'、'fmt '、'ftyp'
    required this.offset, // 块在文件中的字节偏移（含块头）
    required this.size, // 块总字节长度（含块头）
    required this.dataOffset, // 载荷起始偏移
    required this.dataSize, // 载荷字节长度
    this.isOpaque = false, // 未识别类型 / 不透明叶子（不递归）
    this.children = const [],
    this.fields = const [],
  });

  /// 文件里字面的块类型名。
  final String type;

  /// 块在文件中的字节偏移（含块头）。
  final int offset;

  /// 块总字节长度（含块头）。
  final int size;

  /// 载荷起始偏移。
  final int dataOffset;

  /// 载荷字节长度。
  final int dataSize;

  /// 是否是不透明叶子（未识别类型 / 深度超限 / 不再展开）。
  final bool isOpaque;

  /// 子块。
  final List<ContainerNode> children;

  /// 该块里读出的字段。
  final List<SemanticField> fields;

  @override
  String toString() =>
      'ContainerNode($type @$offset+$size, children: ${children.length})';
}
