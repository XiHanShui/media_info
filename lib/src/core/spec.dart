/// 规格表 DSL：声明式描述一个容器的结构。
///
/// 一张 [ContainerSpec] = 一个容器格式（如 WAV / MP4 / Matroska / FLAC）的全部结构描述。
/// 通用引擎（`engine.dart`）按表解析字节，产出统一的节点树。
library;

import 'dart:typed_data';

/// 字段类型。
enum FieldType {
  /// 1 字节无符号整数。
  uint8,

  /// 2 字节无符号整数。
  uint16,

  /// 3 字节无符号整数。
  uint24,

  /// 4 字节无符号整数。
  uint32,

  /// 8 字节无符号整数（> 2^63 的值不可表示）。
  uint64,

  /// 1 字节有符号整数。
  sint8,

  /// 2 字节有符号整数。
  sint16,

  /// 4 字节有符号整数。
  sint32,

  /// 8 字节有符号整数。
  sint64,

  /// 位域（[FieldSpec.bitWidth] 位）。
  bits,

  /// 4 字节 ASCII。
  fourcc,

  /// 字节串。
  bytes,

  /// UTF-8 文本。
  utf8,

  /// 1 bit 布尔值。
  boolean,
}

/// 单个字段的描述。
class FieldSpec {
  const FieldSpec(
    this.name, {
    required this.type,
    this.bitWidth, // type == FieldType.bits 时的位宽
    this.length, // type == FieldType.bytes / utf8 时的固定字节长度
    this.lengthFrom, // type == FieldType.bytes / utf8 时，长度取自哪个字段名
    this.count, // 固定重复次数
    this.countFrom, // 重复次数取自哪个字段名
    this.endian = Endian.big,
    this.defaultValue,
  });

  /// 字段名（英文技术名，与格式规范逐字对照）。
  final String name;

  /// 字段类型。
  final FieldType type;

  /// 位宽，仅 [FieldType.bits] 使用。
  final int? bitWidth;

  /// 固定字节长度，仅 [FieldType.bytes] / [FieldType.utf8] 使用。
  ///
  /// 未给出且未给出 [lengthFrom] 时，字节串/文本读到块载荷末尾。
  final int? length;

  /// 长度取自同一块里的哪个字段（该字段必须是整数值）。
  final String? lengthFrom;

  /// 固定重复次数；给定后该字段的值是一个列表。
  final int? count;

  /// 重复次数取自同一块里的哪个字段（该字段必须是整数值）。
  final String? countFrom;

  /// 字节序，默认大端。
  final Endian endian;

  /// 无法取值时（例如引用的字段不存在）使用的默认值。
  final Object? defaultValue;
}

/// 块头的读法。
class HeaderRule {
  const HeaderRule({
    this.typeBytes = 4, // 类型字段字节数（4 = fourcc）
    this.sizeBytes = 4, // 长度字段字节数
    this.sizeIncludesHeader = true,
    this.sizeZeroMeansToEof = false,
    this.extendedSizeWhenOne = false, // size == 1 → 后续是 64 位长度
    this.unknownSizeAllowed = false, // 长度可以是"未知"哨兵
    this.padTo, // 载荷按 N 字节对齐（RIFF 奇数长度补 1 字节）
    this.vintSize = false, // 长度用变长整数（EBML）
    this.vintId = false, // 类型用变长整数（EBML）
    this.endian = Endian.big, // 长度字段的字节序
    this.sizeFirst = false, // 长度字段排在类型字段之前（ISO BMFF）
    this.prefixBytes = 0, // 容器载荷开头要跳过的字节数（RIFF 的 form type、FLAC 的 fLaC 魔数）
  });

  /// 类型字段字节数。
  final int typeBytes;

  /// 长度字段字节数（[vintSize] 时忽略）。
  final int sizeBytes;

  /// 长度字段是否包含块头本身。
  final bool sizeIncludesHeader;

  /// 长度字段为 0 时表示"一直到文件尾"。
  final bool sizeZeroMeansToEof;

  /// 长度字段为 1 时，后面跟一个 64 位长度。
  final bool extendedSizeWhenOne;

  /// 长度字段可以是"未知长度"哨兵（全 1）。
  final bool unknownSizeAllowed;

  /// 载荷按 N 字节对齐，尾部补零字节。
  final int? padTo;

  /// 长度用 EBML 风格变长整数。
  final bool vintSize;

  /// 类型用 EBML 风格变长整数（节点类型记为 '0x...' 十六进制）。
  final bool vintId;

  /// 长度字段的字节序，默认大端。
  final Endian endian;

  /// 长度字段排在类型字段**之前**（ISO BMFF 的 box 头：`size` + `type`）。
  ///
  /// 默认 false = 类型在前（RIFF / EBML / FLAC 的块头）。
  final bool sizeFirst;

  /// 容器载荷开头要跳过的字节数，跳过之后才是第一个子块。
  ///
  /// 有些容器的载荷不是直接跟子块，而是先跟一段固定的前缀：
  /// - RIFF / AIFF / LIST：载荷开头 4 字节是 form type（`WAVE` / `AIFF` / `INFO`）
  /// - FLAC：载荷开头 4 字节是 `fLaC` 魔数
  ///
  /// 不跳过的话，引擎会把这段前缀当成子块头去读，尺寸字段落在下一个块 id 上，
  /// 报出假的"文件被截断"。默认 0 = 不跳过。
  final int prefixBytes;
}

/// 一个子块的处理方式。
class ChildSpec {
  const ChildSpec({
    required this.type,
    this.fields = const [], // 固定字段，按顺序读
    this.container, // 容器型 → 用这个 spec 递归
    this.opaque = false, // 不透明叶子：只记 type/offset/size
    this.dispatchOn, // 动态 type 分派：按哪个字段的值选二级表
  });

  /// 块类型名（文件里字面的名字）。
  final String type;

  /// 固定字段，按顺序从载荷开头读。
  final List<FieldSpec> fields;

  /// 子块用的容器规格表；有值表示这是容器型块，可递归。
  final ContainerSpec? container;

  /// 不透明叶子：只记 type/offset/size，不读字段、不递归。
  final bool opaque;

  /// 动态 type 分派：读完 [fields] 后，按这个字段的值去当前容器的 children 表里
  /// 找二级 [ChildSpec]。
  final String? dispatchOn;
}

/// 一个容器格式的规格表。
class ContainerSpec {
  const ContainerSpec({
    required this.name, // 'WAV'、'MP4'、'Matroska'、'FLAC'
    required this.header,
    required this.children, // type → 处理方式
    this.rootType, // 根节点的 type 名（缺省用 format 名）
  });

  /// 规格表的名字（也是格式名，如 'WAV'）。
  final String name;

  /// 块头读法。
  final HeaderRule header;

  /// 子块表：type → 处理方式。
  final Map<String, ChildSpec> children;

  /// 根节点的 type 名；缺省用 [name]。
  final String? rootType;

  /// 根节点在结构树里的 type。
  String get effectiveRootType => rootType ?? name;
}
