# 核心 API 契约

> 这是**实现层的强制契约**。所有实现 agent 必须按此落地；签名不匹配会导致并行分支无法合并。
> 术语依 `GLOSSARY.md`（容器 / 块 / 轨道 / 语义字段 / 结构树 / 标签）。

## 分层

```
规格表（声明式数据）  →  通用容器引擎（代码，只写一次）  →  统一节点树
                                                              ↓
                                                    叶子提取器 → 语义字段
```

## 1. 节点模型

`lib/src/core/node.dart`

```dart
/// 字段来源：文件里直接写的 / 我们推算的。
enum FieldOrigin { read, derived }

/// 字段作用域：文件级 / 轨道级。
enum FieldScope { file, track }

/// 语义字段 = 从容器结构解读出的技术属性。
class SemanticField {
  const SemanticField({
    required this.key,      // 英文技术名，如 'sample_rate'——代码标识符，与规范逐字对照
    required this.label,    // 中文显示名，如 '采样率'
    this.value,
    this.unit,              // 'Hz'、'bit'、'px'…
    this.origin = FieldOrigin.read,
    this.scope = FieldScope.file,
    this.trackIndex,        // scope == FieldScope.track 时有效
    this.source,            // 来自哪个块的哪个字段，如 'fmt ' / 'STREAMINFO'
  });

  final String key;
  final String label;
  final Object? value;
  final String? unit;
  final FieldOrigin origin;
  final FieldScope scope;
  final int? trackIndex;
  final String? source;
}

/// 结构树节点 = 容器里的一个块。
class ContainerNode {
  const ContainerNode({
    required this.type,       // 文件里字面的块类型名，如 'moov'、'fmt '、'ftyp'
    required this.offset,     // 块在文件中的字节偏移（含块头）
    required this.size,       // 块总字节长度（含块头）
    required this.dataOffset, // 载荷起始偏移
    required this.dataSize,   // 载荷字节长度
    this.isOpaque = false,    // 未识别类型 / 不透明叶子（不递归）
    this.children = const [],
    this.fields = const [],
  });

  final String type;
  final int offset;
  final int size;
  final int dataOffset;
  final int dataSize;
  final bool isOpaque;
  final List<ContainerNode> children;
  final List<SemanticField> fields;
}
```

**硬约束**：

- 节点**不持有字节内容**，只持有 `offset`/`size`。hex 视图按需从文件读。
- 偏移与长度一律用 Dart 的 `int`（64 位）。
- 未知块**必须**保留为 `isOpaque = true` 的节点出现在树里，不得丢弃。

## 2. 字节源

`lib/src/core/byte_source.dart`

```dart
/// 随机访问的字节源。大文件不整体读入内存。
abstract interface class ByteSource {
  /// 文件总长度（字节）。
  int get length;

  /// 从 [offset] 起读 [length] 个字节；超出文件末尾则抛 TruncatedFile。
  Uint8List read(int offset, int length);
}

/// 文件实现。
class FileByteSource implements ByteSource { ... }
```

## 3. 规格表 DSL

`lib/src/core/spec.dart`

```dart
/// 字段类型。
enum FieldType {
  uint8, uint16, uint24, uint32, uint64,   // 无符号定长
  sint8, sint16, sint32, sint64,           // 有符号定长
  bits,                                     // 位域（bitWidth 位）
  fourcc,                                   // 4 字节 ASCII
  bytes,                                    // 字节串
  utf8,                                     // UTF-8 文本
  boolean,                                  // 1 bit
}

/// 单个字段的描述。
class FieldSpec {
  const FieldSpec(
    this.name, {
    required this.type,
    this.bitWidth,      // type == FieldType.bits 时的位宽
    this.lengthFrom,    // type == FieldType.bytes 时，长度取自哪个字段名
    this.count,         // 固定重复次数
    this.countFrom,     // 重复次数取自哪个字段名
    this.endian = Endian.big,
    this.defaultValue,
  });

  final String name;
  final FieldType type;
  final int? bitWidth;
  final String? lengthFrom;
  final int? count;
  final String? countFrom;
  final Endian endian;
  final Object? defaultValue;
}

/// 块头的读法。
class HeaderRule {
  const HeaderRule({
    this.typeBytes = 4,          // 类型字段字节数（4 = fourcc）
    this.sizeBytes = 4,          // 长度字段字节数
    this.sizeIncludesHeader = true,
    this.sizeZeroMeansToEof = false,
    this.extendedSizeWhenOne = false,  // size == 1 → 后续是 64 位长度
    this.unknownSizeAllowed = false,   // 长度可以是"未知"哨兵
    this.padTo,                 // 载荷按 N 字节对齐（RIFF 奇数长度补 1 字节）
    this.vintSize = false,      // 长度用变长整数（EBML）
    this.vintId = false,        // 类型用变长整数（EBML）
  });

  final int typeBytes;
  final int sizeBytes;
  final bool sizeIncludesHeader;
  final bool sizeZeroMeansToEof;
  final bool extendedSizeWhenOne;
  final bool unknownSizeAllowed;
  final int? padTo;
  final bool vintSize;
  final bool vintId;
}

/// 一个子块的处理方式。
class ChildSpec {
  const ChildSpec({
    required this.type,
    this.fields = const [],     // 固定字段，按顺序读
    this.container,             // 容器型 → 用这个 spec 递归
    this.opaque = false,        // 不透明叶子：只记 type/offset/size
    this.dispatchOn,            // 动态 type 分派：按哪个字段的值选二级表
  });

  final String type;
  final List<FieldSpec> fields;
  final ContainerSpec? container;
  final bool opaque;
  final String? dispatchOn;
}

/// 一个容器格式的规格表。
class ContainerSpec {
  const ContainerSpec({
    required this.name,          // 'WAV'、'MP4'、'Matroska'、'FLAC'
    required this.header,
    required this.children,      // type → 处理方式
    this.rootType,               // 根节点的 type 名（缺省用 format 名）
  });

  final String name;
  final HeaderRule header;
  final Map<String, ChildSpec> children;
  final String? rootType;
}
```

**引擎必须支持的语义**：

- 长度字段：`sizeBytes` 字节、含头与否、0 表示到文件尾、`size == 1` 时的 64 位扩展、变长整数（VINT）、"未知长度"哨兵。
- 字段：定长整数（大小端）、位域、fourcc、字节串（定长或由前一字段决定长度）、UTF-8、布尔位、计数前缀数组（次数由前一字段决定）。
- 动态 type 分派：`dispatchOn` 指定的字段值决定用哪个二级 `ChildSpec`。
- **"未知即跳过"兜底**：表里查不到的 type 一律产出 `isOpaque = true` 的节点，不递归、不报错。
- 递归深度上限（防环）：默认 64 层，超出即停并标记不透明。

## 4. 通用容器引擎

`lib/src/core/engine.dart`

```dart
/// 解析结果。
class ParseResult {
  const ParseResult({required this.root, this.truncated = false, this.error});
  final ContainerNode root;
  final bool truncated;   // 文件被截断
  final String? error;    // 面向用户的中文错误说明
}

/// 解析一个容器。
///
/// [depth] 控制惰性展开：0 = 只建根节点的第一层子块。
ParseResult parseContainer(ContainerSpec spec, ByteSource source, {int depth = 1});
```

**行为约定**：

- 读到的字节少于声明长度 → 立即停止，`truncated = true`，`error` 给出可展示的中文说明（"文件在偏移 X 处截断，声明长度还差 N 字节"），**已解析的部分结构照常返回**。
- 长度字段撒谎（声明长度 > 实际剩余）走同一条截断路径，不越界、不无限读。
- 引擎**不抛异常**给 UI 层；错误通过 `ParseResult.error` 传达。

## 5. 叶子提取器

`lib/src/core/extractor.dart`

```dart
/// 从已解析的树里取语义字段。不重复解析字节。
typedef LeafExtractor = List<SemanticField> Function(ContainerNode root);
```

## 6. 格式注册表

`lib/src/core/registry.dart`

```dart
class FormatSpec {
  const FormatSpec({
    required this.name,          // 'WAV'、'MP4'、'Matroska'、'FLAC'、'MP3'
    required this.container,      // ContainerSpec
    this.extractor,              // 叶子提取器
    this.detect,                 // 嗅探：从文件头判断是不是这个格式
  });

  final String name;
  final ContainerSpec container;
  final LeafExtractor? extractor;
  final bool Function(ByteSource)? detect;
}

/// 全部已注册格式，按嗅探顺序排列。
List<FormatSpec> allFormats();

/// 按内容嗅探选出一个格式；识别不出返回 null。
FormatSpec? detectFormat(ByteSource source);
```

**扩展点**：加一个新容器 = 写一张 `ContainerSpec` 表 + 注册一行。注册表登记的是**规格表 + 可选的叶子提取器**，不是解析器对象。

## 7. 标签

`lib/src/core/tag.dart`

```dart
/// 标签 = 作者写进文件的元数据（与技术属性分开）。
class Tag {
  const Tag({required this.key, this.value, this.source});
  final String key;      // 英文原名，不翻译
  final Object? value;   // String（文本）或 Uint8List（二进制，如封面）
  final String? source;  // 来自哪个块：'ilst' / 'VORBIS_COMMENT' / 'ID3v2'
}

/// 标签的收集结果。
///
/// [source] 是字节源：标签载荷（`data` 盒、Vorbis 注释、ID3 帧体）要现读字节，
/// 所以不传字节源就解不出标签（返回空列表）。
List<Tag> collectTags(ContainerNode root, {ByteSource? source});
```

MP4 的 `udta`/`meta`/`ilst`、FLAC 的 Vorbis Comment、MP3 的 ID3v2 各自实现，产出统一的 `Tag` 列表。

- **key 保留英文原名**（`©nam`、`TITLE`、`TIT2` 都不翻译）。
- **value 只有两种形态**：`String`（文本）与 `Uint8List`（二进制，如 `covr` 封面）。
- **坏掉的标签区域跳过，不抛异常**：不认识的标签类型、长度撒谎、缺字节都只是跳过，
  不影响同一文件里的其它标签。
- 覆盖范围：MP4 `ilst`（含二进制封面）、FLAC `VORBIS_COMMENT`、MP3 ID3v2.3/2.4 的
  文本帧 `T***`（ID3v1 与 Matroska 的 Tags 不在本 MVP 范围）。

## 8. 错误类型

`lib/src/core/errors.dart`

```dart
/// 读到的字节少于声明长度。
class TruncatedFile implements Exception {
  TruncatedFile(this.offset, this.missingBytes);
  final int offset;
  final int missingBytes;
}
```
