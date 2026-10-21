/// FLAC 格式：元数据块规格表 + 语义字段提取器。
///
/// 依据 RFC 9639《FLAC》（2024-12）。
///
/// **为什么块头要手写**：FLAC 的元数据块头是 **1 bit `last-metadata-block` +
/// 7 bit 类型 + 24 bit 长度**（大端，长度不含这 4 字节）。通用引擎的
/// [HeaderRule] 只能表达「N 字节类型 + M 字节长度」，表达不了那个标志位，
/// 核心是冻结的，所以块头的读取在 [parseFlac] 里手写；**块载荷的字段**仍然
/// 按 [flacContainerSpec] 这张表交给通用引擎的字段读取器解码
/// （位域、字节序、长度前缀都走引擎，不在格式模块里复制一份）。
///
/// **结构**：FLAC 只有两层——根节点（整个文件）→ 元数据块序列。
/// 元数据块之后的音频帧区不解析（按调研结论，它在结构树里只是一个不透明
/// 的连续区，由根节点的总长度覆盖）。
library;

import 'dart:typed_data';

import '../core/byte_source.dart';
import '../core/engine.dart';
import '../core/errors.dart';
import '../core/node.dart';
import '../core/registry.dart';
import '../core/spec.dart';

/// FLAC 魔数：文件头 4 字节。
const String flacMagic = 'fLaC';

/// 元数据块类型码 → 规范名（RFC 9639 §8.1）。
///
/// 7..126 是保留类型，127 是禁止类型；表里没有的按 `UNKNOWN` 处理。
const Map<int, String> flacMetadataBlockTypes = <int, String>{
  0: 'STREAMINFO',
  1: 'PADDING',
  2: 'APPLICATION',
  3: 'SEEKTABLE',
  4: 'VORBIS_COMMENT',
  5: 'CUESHEET',
  6: 'PICTURE',
};

/// STREAMINFO 的位域字段（RFC 9639 §8.2）。
///
/// 规范把声道数与每样本位数存成「真实值减一」，所以字段名带 `_minus_one`
/// 后缀，读出来后加一才是真实值。
const List<FieldSpec> _streamInfoFields = <FieldSpec>[
  FieldSpec('min_block_size', type: FieldType.uint16),
  FieldSpec('max_block_size', type: FieldType.uint16),
  FieldSpec('min_frame_size', type: FieldType.uint24),
  FieldSpec('max_frame_size', type: FieldType.uint24),
  FieldSpec('sample_rate', type: FieldType.bits, bitWidth: 20),
  FieldSpec('channels_minus_one', type: FieldType.bits, bitWidth: 3),
  FieldSpec('bits_per_sample_minus_one', type: FieldType.bits, bitWidth: 5),
  FieldSpec('total_samples', type: FieldType.bits, bitWidth: 36),
  FieldSpec('md5', type: FieldType.bytes, length: 16),
];

/// VORBIS_COMMENT 的字段（RFC 9639 §8.6）。
///
/// 长度字段是**小端**——FLAC 里唯一的字节序例外（§5）。
const List<FieldSpec> _vorbisCommentFields = <FieldSpec>[
  FieldSpec('vendor_length', type: FieldType.uint32, endian: Endian.little),
  FieldSpec('vendor', type: FieldType.utf8, lengthFrom: 'vendor_length'),
  FieldSpec('field_count', type: FieldType.uint32, endian: Endian.little),
];

/// FLAC 的容器规格表（声明式）。
///
/// [HeaderRule] 描述的是元数据块的块头：1 字节类型（最高位是
/// `last-metadata-block` 标志）+ 3 字节大端长度，长度不含块头。
///
/// ⚠️ **不要用 `parseContainer(flacContainerSpec, …)` 解析 FLAC**：通用引擎的
/// 容器遍历从偏移 0 开始，会把文件级魔数 `fLaC` 当成块头读。请用
/// [parseFlac]（或 [parseFormatContainer]）。
final ContainerSpec flacContainerSpec = ContainerSpec(
  name: 'FLAC',
  rootType: 'FLAC',
  header: const HeaderRule(
    typeBytes: 1,
    sizeBytes: 3,
    sizeIncludesHeader: false,
    endian: Endian.big,
  ),
  children: <String, ChildSpec>{
    'STREAMINFO': const ChildSpec(
      type: 'STREAMINFO',
      fields: _streamInfoFields,
    ),
    // PADDING / APPLICATION 的载荷是纯字节（长度由块头决定），不透明叶子。
    'PADDING': const ChildSpec(type: 'PADDING', opaque: true),
    'APPLICATION': const ChildSpec(type: 'APPLICATION', opaque: true),
    'SEEKTABLE': const ChildSpec(type: 'SEEKTABLE', opaque: true),
    'VORBIS_COMMENT': const ChildSpec(
      type: 'VORBIS_COMMENT',
      fields: _vorbisCommentFields,
    ),
    'CUESHEET': const ChildSpec(type: 'CUESHEET', opaque: true),
    'PICTURE': const ChildSpec(type: 'PICTURE', opaque: true),
  },
);

/// FLAC 自己的字段名 → 中文显示名。
const Map<String, String> _fieldLabels = <String, String>{
  'min_block_size': '最小块大小',
  'max_block_size': '最大块大小',
  'min_frame_size': '最小帧大小',
  'max_frame_size': '最大帧大小',
  'sample_rate': '采样率',
  'channels': '声道数',
  'bits_per_sample': '每样本位数',
  'total_samples': '总采样数',
  'md5': 'MD5 校验和',
  'vendor_length': '厂商串长度',
  'vendor': '厂商标识',
  'field_count': '标签数量',
};

/// 字段的单位。
const Map<String, String> _fieldUnits = <String, String>{
  'sample_rate': 'Hz',
  'bits_per_sample': 'bit',
};

/// 规范里存的是「真实值减一」的字段 → 规范里的字段名。
const Map<String, String> _minusOneNames = <String, String>{
  'channels_minus_one': 'channels',
  'bits_per_sample_minus_one': 'bits_per_sample',
};

/// 解析一个 FLAC 文件，产出结构树。
///
/// 根节点是整个文件（`type` = `FLAC`），子节点是元数据块序列。
/// 块被截断时**留在树里**，长度裁到实际可用的字节数并标记 `isOpaque`。
///
/// [depth] 与 [maxDepth] 只是为了跟 [parseContainer] 的调用形状一致：
/// FLAC 只有两层，没有更深的子块，所以它们不改变结果。
ParseResult parseFlac(
  ByteSource source, {
  int depth = 1,
  int maxDepth = kMaxRecursionDepth,
}) {
  final length = source.length;
  final children = <ContainerNode>[];
  var truncated = false;
  String? error;

  if (length < flacMagic.length) {
    return ParseResult(
      root: ContainerNode(
        type: 'FLAC',
        offset: 0,
        size: length,
        dataOffset: 0,
        dataSize: length,
      ),
      truncated: true,
      error: '文件只有 $length 字节，不足以容纳 FLAC 魔数',
    );
  }
  final magic = String.fromCharCodes(source.read(0, flacMagic.length));
  if (magic != flacMagic) {
    return ParseResult(
      root: ContainerNode(
        type: 'FLAC',
        offset: 0,
        size: length,
        dataOffset: 0,
        dataSize: length,
      ),
      error: '文件头不是 FLAC 魔数 $flacMagic',
    );
  }

  var pos = flacMagic.length;
  var isLastBlock = false;
  while (!isLastBlock && pos < length) {
    if (pos + 4 > length) {
      truncated = true;
      error = '文件在偏移 $pos 处截断，元数据块头不完整';
      break;
    }
    final header = source.read(pos, 4);
    isLastBlock = (header[0] & 0x80) != 0;
    final typeCode = header[0] & 0x7F;
    final blockLength = (header[1] << 16) | (header[2] << 8) | header[3];
    final payloadStart = pos + 4;
    final available = length - payloadStart;
    final typeName = flacMetadataBlockTypes[typeCode] ?? 'UNKNOWN';
    final child = flacContainerSpec.children[typeName];

    if (blockLength > available) {
      // 截断：块留在树里，长度裁到实际可用的字节数。
      truncated = true;
      error = '文件在偏移 $payloadStart 处截断，声明长度还差 ${blockLength - available} 字节';
      children.add(
        ContainerNode(
          type: typeName,
          offset: pos,
          size: 4 + available,
          dataOffset: payloadStart,
          dataSize: available,
          isOpaque: true,
          fields: _decodeBlockFields(
            source,
            payloadStart,
            available,
            child,
          ).fields,
        ),
      );
      break;
    }

    var fields = const <SemanticField>[];
    var opaque = child == null || child.opaque;
    if (child != null && !child.opaque) {
      final decoded = _decodeBlockFields(
        source,
        payloadStart,
        blockLength,
        child,
      );
      fields = decoded.fields;
      opaque = decoded.truncated;
    }
    children.add(
      ContainerNode(
        type: typeName,
        offset: pos,
        size: 4 + blockLength,
        dataOffset: payloadStart,
        dataSize: blockLength,
        isOpaque: opaque,
        fields: fields,
      ),
    );
    pos = payloadStart + blockLength;
  }

  final root = ContainerNode(
    type: 'FLAC',
    offset: 0,
    size: length,
    dataOffset: 0,
    dataSize: length,
    children: children,
  );
  return ParseResult(root: root, truncated: truncated, error: error);
}

/// 叶子提取器：从已解析的结构树里取 FLAC 的语义字段。
///
/// 统一词表字段在这里产出（中文显示名）；格式特有的 `total_samples` 与
/// `md5` **不进统一词表**，它们挂在 STREAMINFO 节点上。
List<SemanticField> extractFlacFields(ContainerNode root) {
  final fields = <SemanticField>[
    const SemanticField(
      key: 'codec',
      label: '编码标识',
      value: 'FLAC',
      scope: FieldScope.track,
      trackIndex: 0,
      source: 'FLAC',
    ),
  ];

  final streamInfo = _findStreamInfo(root);
  if (streamInfo == null) return fields;

  final values = <String, Object?>{
    for (final field in streamInfo.fields) field.key: field.value,
  };
  final sampleRate = _intValue(values, 'sample_rate');
  final channels = _intValue(
    values,
    'channels',
    minusOneKey: 'channels_minus_one',
  );
  final bitDepth = _intValue(
    values,
    'bits_per_sample',
    minusOneKey: 'bits_per_sample_minus_one',
  );
  final totalSamples = _intValue(values, 'total_samples');

  if (sampleRate != null) {
    fields.add(
      SemanticField(
        key: 'sample_rate',
        label: '采样率',
        value: sampleRate,
        unit: 'Hz',
        scope: FieldScope.track,
        trackIndex: 0,
        source: 'FLAC STREAMINFO',
        byteRange: byteRangeOf(streamInfo, 'sample_rate'),
      ),
    );
  }
  if (bitDepth != null) {
    fields.add(
      SemanticField(
        key: 'bit_depth',
        label: '位深',
        value: bitDepth,
        unit: 'bit',
        scope: FieldScope.track,
        trackIndex: 0,
        source: 'FLAC STREAMINFO',
        // 位深是 "bits_per_sample_minus_one + 1"——指向它真正读的那几个字节。
        byteRange: byteRangeOf(streamInfo, 'bits_per_sample'),
      ),
    );
  }
  if (channels != null) {
    fields.add(
      SemanticField(
        key: 'channels',
        label: '声道数',
        value: channels,
        scope: FieldScope.track,
        trackIndex: 0,
        source: 'FLAC STREAMINFO',
        // 声道数同样是 "channels_minus_one + 1"。
        byteRange: byteRangeOf(streamInfo, 'channels'),
      ),
    );
  }
  if (sampleRate != null && totalSamples != null && sampleRate > 0) {
    final duration = totalSamples / sampleRate;
    fields.add(
      SemanticField(
        key: 'duration',
        label: '时长',
        value: duration,
        unit: 's',
        origin: FieldOrigin.derived,
        source: 'FLAC STREAMINFO',
      ),
    );
    if (root.size > 0) {
      fields.add(
        SemanticField(
          key: 'overall_bitrate',
          label: '平均码率',
          value: root.size * 8 / duration,
          unit: 'bit/s',
          origin: FieldOrigin.derived,
          source: 'FLAC',
        ),
      );
    }
  }
  return fields;
}

/// FLAC 的格式注册项。
final FormatSpec flacFormat = FormatSpec(
  name: 'FLAC',
  container: flacContainerSpec,
  extractor: extractFlacFields,
  detect: isFlacFile,
  // FLAC 必须走自己的解析器：通用引擎表达不了文件级魔数 `fLaC`，也表达不了块头的
  // `last-metadata-block` 标志位——直接 parseContainer 会把魔数当成块头读，结果是错的。
  // 挂了 parser 之后，调用方统一走核心的 parseFormat()，不需要按格式分支。
  parser: parseFlac,
);

/// 把 FLAC 注册进全局格式注册表。
void registerFlacFormat() => registerFormat(flacFormat);

/// 按内容嗅探：文件头是不是 FLAC 魔数。
bool isFlacFile(ByteSource source) {
  if (source.length < flacMagic.length) return false;
  return String.fromCharCodes(source.read(0, flacMagic.length)) == flacMagic;
}

// ---------------------------------------------------------------------------
// 内部实现
// ---------------------------------------------------------------------------

/// 一个块载荷的解码结果。
class _DecodedFields {
  const _DecodedFields(this.fields, this.truncated);

  final List<SemanticField> fields;

  /// 载荷不够长，字段没读全。
  final bool truncated;
}

/// 用通用引擎的字段读取器解码一个块载荷的字段。
///
/// 引擎的容器遍历总是从字节源的偏移 0 开始，所以这里用一个「窗口」字节源把
/// 载荷单独框出来，再用一张「只有一个子块、没有块头」的规格表驱动它——
/// 位域的位序、大小端、长度前缀全部走引擎，不在格式模块里复制一份。
_DecodedFields _decodeBlockFields(
  ByteSource source,
  int offset,
  int length,
  ChildSpec? child,
) {
  if (child == null || child.opaque || length <= 0) {
    return const _DecodedFields(<SemanticField>[], false);
  }
  final window = _WindowByteSource(source, offset, length);
  final spec = ContainerSpec(
    name: 'FLAC_BLOCK',
    header: const HeaderRule(typeBytes: 0, sizeBytes: 0),
    children: <String, ChildSpec>{'': child},
  );
  final result = parseContainer(spec, window, depth: 1);
  final node = result.root.children.isEmpty ? null : result.root.children.first;
  final raw = node?.fields ?? const <SemanticField>[];
  return _DecodedFields(
    // 窗口内的偏移要还原成文件里的绝对偏移，否则字段的字节范围指错了地方。
    _localize(raw, node?.type ?? child.type, baseOffset: offset),
    result.truncated || (node?.isOpaque ?? false),
  );
}

/// 把引擎解出的原始字段转成节点上挂的语义字段：规范里的真实值 + 中文显示名。
List<SemanticField> _localize(
  List<SemanticField> raw,
  String blockType, {
  int baseOffset = 0,
}) {
  final out = <SemanticField>[];
  for (final field in raw) {
    final range = field.byteRange;
    final byteRange = range == null
        ? null
        : ByteRange(range.start + baseOffset, range.end + baseOffset);
    final name = _minusOneNames[field.key] ?? field.key;
    final value = _minusOneNames.containsKey(field.key)
        ? (field.value as int) + 1
        : field.value;
    out.add(
      SemanticField(
        key: name,
        label: _fieldLabels[name] ?? name,
        value: name == 'md5' ? _toHex(value) : value,
        unit: _fieldUnits[name],
        origin: FieldOrigin.read,
        source: blockType,
        byteRange: byteRange,
      ),
    );
  }
  return out;
}

/// 找出 STREAMINFO 节点。
///
/// 兼容两种形态：本模块解析出来的节点类型是规范名 `STREAMINFO`；
/// 直接用通用引擎解析时类型会是类型字节本身（`\x00`）。
ContainerNode? _findStreamInfo(ContainerNode root) {
  for (final child in root.children) {
    if (child.type == 'STREAMINFO' || child.type == '\x00') return child;
    final nested = _findStreamInfo(child);
    if (nested != null) return nested;
  }
  return null;
}

/// 取一个整数字段；[minusOneKey] 是「真实值减一」存法的备用键。
int? _intValue(Map<String, Object?> values, String key, {String? minusOneKey}) {
  final direct = values[key];
  if (direct is int) return direct;
  if (minusOneKey != null) {
    final raw = values[minusOneKey];
    if (raw is int) return raw + 1;
  }
  return null;
}

/// 字节串转小写十六进制。
String _toHex(Object? value) {
  if (value is! Uint8List) return '$value';
  final buffer = StringBuffer();
  for (final byte in value) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

/// 只暴露一段字节的字节源（给通用引擎当载荷窗口用）。
class _WindowByteSource implements ByteSource {
  const _WindowByteSource(this._source, this._offset, this._length);

  final ByteSource _source;
  final int _offset;
  final int _length;

  @override
  int get length => _length;

  @override
  Uint8List read(int offset, int length) {
    if (offset < 0 || length < 0 || offset + length > _length) {
      throw TruncatedFile(_offset + offset, offset + length - _length);
    }
    return _source.read(_offset + offset, length);
  }
}
