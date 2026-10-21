/// RIFF 家族（WAV / AIFF）的规格表 + 叶子提取器。
///
/// 结构分三层（见 `docs/design/core-api.md`）：
/// - **规格表**（本文件）：RIFF/AIFF 的块头规则与各块载荷的字段表；
/// - **通用容器引擎**（`core/engine.dart`）：按表读块头、读字段、产出统一节点树；
/// - **叶子提取器**（本文件）：从已解析的树里取统一词表里的语义字段。
///
/// ## 为什么 RIFF / AIFF 需要自己的解析入口
///
/// RIFF 的块结构是「`id`(4) + `size`(LE32) + **form type**(4) + 子块」，
/// AIFF 是「`FORM` + `size`(BE32) + **form type**(`AIFF`) + 子块」，
/// `LIST` 同样带一个 list type（`INFO`）。
///
/// 核心引擎的规格表 DSL 里，容器的子块永远从「容器块载荷的起点」开始解析，
/// 没有"块载荷开头先跳过一个 form type"这个概念——form type 会被当成第一个块头读，
/// 于是把后一个块的 id 误读成长度，直接走进截断分支。
///
/// 因此本模块用**窗口字节源**（`_WindowSource`）把子块列表单独切出来交给核心引擎解析，
/// 再把偏移量平移回原文件（`_rebase`）。块头规则、字段表、截断降级、
/// 「未知块 → 不透明叶子」这些逻辑全部复用核心引擎，没有第二套解析器。
///
/// ## 用法
///
/// ```dart
/// final result = parseWav(source);             // 完整结构树
/// final fields = extractWavFields(result.root); // 统一语义字段
/// ```
///
/// 注意：**不要用 `parseContainer(wavFormat.container, source)` 拿完整结构树**——
/// 核心引擎无法表达"容器块头后面跟着一个 form type"，那样只能拿到顶层
/// `RIFF` / `FORM` 块（见 [wavSpec] / [aiffSpec] 的说明）。应用层请调
/// [parseWav] / [parseAiff]。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../core/byte_source.dart';
import '../core/engine.dart';
import '../core/node.dart';
import '../core/registry.dart';
import '../core/spec.dart';

// ---------------------------------------------------------------------------
// 规格表
// ---------------------------------------------------------------------------

/// 容器型块（`RIFF` / `FORM` / `LIST`）的 form type 长度（字节）。
const int _formTypeLength = 4;

/// 带 form type 的容器型块类型。
///
/// 这些块的载荷开头是 4 字节 form type / list type，后面才是子块列表。
const Set<String> _containerChunkTypes = <String>{'RIFF', 'FORM', 'LIST'};

/// RIFF 块头规则：`id`(4) + `size`(LE32) + 载荷（长度**不含**块头）。
///
/// - `sizeIncludesHeader: false` —— RIFF 的长度只算载荷，不含 8 字节块头；
/// - `endian: Endian.little` —— 长度字段是小端（AIFF 是大端，见 [aiffChunkHeader]）；
/// - `padTo: 2` —— 载荷是奇数长度时补 1 个对齐字节；
/// - `unknownSizeAllowed: true` —— `0xFFFFFFFF` 是 RIFF 约定的"长度未知"哨兵
///   （流式写入的文件会这么写），此时载荷一直到块末尾。
const HeaderRule riffChunkHeader = HeaderRule(
  typeBytes: 4,
  sizeBytes: 4,
  sizeIncludesHeader: false,
  endian: Endian.little,
  padTo: 2,
  unknownSizeAllowed: true,
);

/// AIFF 块头规则：与 [riffChunkHeader] 相同，但长度字段是**大端**。
const HeaderRule aiffChunkHeader = HeaderRule(
  typeBytes: 4,
  sizeBytes: 4,
  sizeIncludesHeader: false,
  endian: Endian.big,
  padTo: 2,
  unknownSizeAllowed: true,
);

/// `fmt ` 载荷里 `cbSize` 之后那一段扩展的字段（WAVEFORMATEXTENSIBLE 用）。
///
/// 表只能表达"定长头 + N 字节扩展"（N 由 `cbSize` 自描述），
/// 扩展里**是什么**要按 `wFormatTag` 分派后手写解码——见 [decodeWaveFormatExExtension]。
const FieldSpec _fmtExtensionField = FieldSpec(
  'extension',
  type: FieldType.bytes,
  lengthFrom: 'cbSize',
);

/// `fmt ` 载荷里自描述的扩展长度（`cbSize`）。
const FieldSpec _fmtCbSizeField = FieldSpec(
  'cbSize',
  type: FieldType.uint16,
  endian: Endian.little,
);

/// WAV 内部 chunk 列表的规格表。
///
/// `fmt ` 的载荷是 **tagged union**：`wFormatTag` 决定它是 WAVEFORMATEX 还是
/// WAVEFORMATEXTENSIBLE，末尾还有 `cbSize` 自描述的扩展。这里用引擎的动态分派
/// （`dispatchOn`）表达这个 union：
/// - `1` = WAVE_FORMAT_PCM：定长 16 字节的 WAVEFORMATEX，**没有** `cbSize`；
/// - `3` = WAVE_FORMAT_IEEE_FLOAT：WAVEFORMATEX + `cbSize` + 扩展；
/// - `65534` = WAVE_FORMAT_EXTENSIBLE：WAVEFORMATEX + `cbSize` + 扩展。
///
/// 未登记的 `wFormatTag` 会让 `fmt ` 降级成不透明节点（但已读出的字段保留）。
const ContainerSpec wavChunkSpec = ContainerSpec(
  name: 'WAV chunks',
  header: riffChunkHeader,
  children: <String, ChildSpec>{
    'fmt ': ChildSpec(
      type: 'fmt ',
      fields: <FieldSpec>[
        FieldSpec('wFormatTag', type: FieldType.uint16, endian: Endian.little),
        FieldSpec('channels', type: FieldType.uint16, endian: Endian.little),
        FieldSpec('sample_rate', type: FieldType.uint32, endian: Endian.little),
        FieldSpec('byte_rate', type: FieldType.uint32, endian: Endian.little),
        FieldSpec('block_align', type: FieldType.uint16, endian: Endian.little),
        FieldSpec('bit_depth', type: FieldType.uint16, endian: Endian.little),
      ],
      dispatchOn: 'wFormatTag',
    ),
    'data': ChildSpec(type: 'data'),
    'LIST': ChildSpec(
      type: 'LIST',
      fields: <FieldSpec>[FieldSpec('list_type', type: FieldType.fourcc)],
    ),
    'fact': ChildSpec(
      type: 'fact',
      fields: <FieldSpec>[
        FieldSpec(
          'num_sample_frames',
          type: FieldType.uint32,
          endian: Endian.little,
        ),
      ],
    ),
    // --- `fmt ` 载荷 tagged union 的分派表（键 = wFormatTag 的十进制字符串）---
    '1': ChildSpec(type: '1'),
    '3': ChildSpec(
      type: '3',
      fields: <FieldSpec>[_fmtCbSizeField, _fmtExtensionField],
    ),
    '65534': ChildSpec(
      type: '65534',
      fields: <FieldSpec>[_fmtCbSizeField, _fmtExtensionField],
    ),
  },
);

/// AIFF 内部 chunk 列表的规格表。
///
/// `COMM` 载荷是定长字段：`numChannels`(u16) / `numSampleFrames`(u32) /
/// `sampleSize`(u16) / `sampleRate`（80 位 IEEE-754 扩展精度浮点）。
/// 规格表 DSL 没有 80 位浮点类型，所以采样率按 10 字节原样读出，
/// 由 [decodeExtended80] 在手写侧换算。
const ContainerSpec aiffChunkSpec = ContainerSpec(
  name: 'AIFF chunks',
  header: aiffChunkHeader,
  children: <String, ChildSpec>{
    'COMM': ChildSpec(
      type: 'COMM',
      fields: <FieldSpec>[
        FieldSpec('num_channels', type: FieldType.uint16, endian: Endian.big),
        FieldSpec(
          'num_sample_frames',
          type: FieldType.uint32,
          endian: Endian.big,
        ),
        FieldSpec('sample_size', type: FieldType.uint16, endian: Endian.big),
        FieldSpec('sample_rate', type: FieldType.bytes, length: 10),
      ],
    ),
    'SSND': ChildSpec(
      type: 'SSND',
      fields: <FieldSpec>[
        FieldSpec('offset', type: FieldType.uint32, endian: Endian.big),
        FieldSpec('block_size', type: FieldType.uint32, endian: Endian.big),
      ],
    ),
  },
);

/// WAV 顶层规格表：整个文件是一个 `RIFF` 块，块头之后是 form type `WAVE`。
///
/// ⚠️ 这张表只描述**顶层**：`parseContainer(wavSpec, source)` 只能拿到 `RIFF` 块本身
/// （form type 记在它的 `form_type` 字段里），子块列表要靠 [parseWav]。
const ContainerSpec wavSpec = ContainerSpec(
  name: 'WAV',
  header: riffChunkHeader,
  children: <String, ChildSpec>{
    'RIFF': ChildSpec(
      type: 'RIFF',
      fields: <FieldSpec>[FieldSpec('form_type', type: FieldType.fourcc)],
    ),
  },
);

/// AIFF 顶层规格表：整个文件是一个 `FORM` 块，块头之后是 form type `AIFF`。
///
/// ⚠️ 同 [wavSpec]：完整结构树要靠 [parseAiff]。
const ContainerSpec aiffSpec = ContainerSpec(
  name: 'AIFF',
  header: aiffChunkHeader,
  children: <String, ChildSpec>{
    'FORM': ChildSpec(
      type: 'FORM',
      fields: <FieldSpec>[FieldSpec('form_type', type: FieldType.fourcc)],
    ),
  },
);

// ---------------------------------------------------------------------------
// 解析
// ---------------------------------------------------------------------------

/// 只暴露源文件 `[base, end)` 区间的字节源视图。
///
/// 用来把「容器块载荷里 form type 之后的那段」切成一个独立的字节区间，
/// 交给核心引擎按规格表解析。
class _WindowSource implements ByteSource {
  _WindowSource(this.source, this.base, this.end);

  /// 底层字节源（整个文件）。
  final ByteSource source;

  /// 窗口在源文件里的起始偏移。
  final int base;

  /// 窗口在源文件里的结束偏移（不含）。
  final int end;

  @override
  int get length => end - base;

  @override
  Uint8List read(int offset, int length) => source.read(base + offset, length);
}

/// 把窗口里解析出来的节点整体平移回原文件的偏移。
ContainerNode _rebase(ContainerNode node, int base) {
  return ContainerNode(
    type: node.type,
    offset: node.offset + base,
    size: node.size,
    dataOffset: node.dataOffset + base,
    dataSize: node.dataSize,
    isOpaque: node.isOpaque,
    fields: node.fields,
    children: node.children.map((child) => _rebase(child, base)).toList(),
  );
}

/// 汇总多次引擎调用的截断/错误信息（先到先得，与引擎行为一致）。
class _ParseState {
  bool truncated = false;
  String? error;

  /// 吸收一次引擎调用的结果。
  ///
  /// [offsetFix] 是这次调用用的字节源窗口在原文件里的起点——窗口里的偏移量
  /// 是相对窗口的，要平移回原文件坐标才能给用户看。
  void absorb(ParseResult result, [int offsetFix = 0]) {
    if (result.truncated) truncated = true;
    final message = result.error;
    if (message != null && error == null) {
      error = offsetFix == 0 ? message : _shiftOffsets(message, offsetFix);
    }
  }
}

/// 把错误说明里的偏移量从窗口坐标平移到原文件坐标。
String _shiftOffsets(String message, int base) {
  return message.replaceAllMapped(
    RegExp(r'偏移 (\d+)'),
    (match) => '偏移 ${int.parse(match.group(1)!) + base}',
  );
}

/// 展开一个容器型节点的子块。
///
/// 容器型块（`RIFF` / `FORM` / `LIST`）的载荷开头是 4 字节 form type，
/// 子块列表从 `dataOffset + 4` 开始。
ContainerNode _expandContainer(
  ContainerNode node,
  ByteSource source,
  ContainerSpec chunkSpec,
  int level,
  int depth,
  _ParseState state,
) {
  if (!_containerChunkTypes.contains(node.type)) return node;
  if (level + 1 > depth) return node;

  final childStart = node.dataOffset + _formTypeLength;
  final childEnd = node.dataOffset + node.dataSize;
  if (childStart > childEnd) return node;

  final window = _WindowSource(source, childStart, childEnd);
  final result = parseContainer(chunkSpec, window, depth: 1);
  state.absorb(result, childStart);

  final children = <ContainerNode>[];
  for (final child in result.root.children) {
    final rebased = _rebase(child, childStart);
    children.add(
      _expandContainer(rebased, source, chunkSpec, level + 1, depth, state),
    );
  }

  return ContainerNode(
    type: node.type,
    offset: node.offset,
    size: node.size,
    dataOffset: node.dataOffset,
    dataSize: node.dataSize,
    isOpaque: node.isOpaque,
    fields: node.fields,
    children: children,
  );
}

/// 解析 RIFF / AIFF 家族的结构树。
///
/// [formatSpec] 是顶层规格表（`RIFF` / `FORM` 那一个块），
/// [chunkSpec] 是容器内部的 chunk 列表规格表。
///
/// [depth] 是展开的层数：1 = 只建顶层块，2 = 再建容器块里的子块，3 = 再往下建一层。
ParseResult parseRiffTree(
  ByteSource source,
  ContainerSpec formatSpec,
  ContainerSpec chunkSpec, {
  int depth = 3,
}) {
  final top = parseContainer(formatSpec, source, depth: 1);
  final state = _ParseState()..absorb(top);

  final children = <ContainerNode>[];
  for (final node in top.root.children) {
    children.add(_expandContainer(node, source, chunkSpec, 1, depth, state));
  }

  final root = ContainerNode(
    type: top.root.type,
    offset: top.root.offset,
    size: top.root.size,
    dataOffset: top.root.dataOffset,
    dataSize: top.root.dataSize,
    isOpaque: top.root.isOpaque,
    fields: top.root.fields,
    children: children,
  );
  return ParseResult(
    root: root,
    truncated: state.truncated,
    error: state.error,
  );
}

/// 解析 WAV（RIFF）文件的结构树。
ParseResult parseWav(ByteSource source, {int depth = 3}) =>
    parseRiffTree(source, wavSpec, wavChunkSpec, depth: depth);

/// 解析 AIFF（FORM）文件的结构树。
ParseResult parseAiff(ByteSource source, {int depth = 3}) =>
    parseRiffTree(source, aiffSpec, aiffChunkSpec, depth: depth);

// ---------------------------------------------------------------------------
// 手写逃生口
// ---------------------------------------------------------------------------

/// 把 AIFF `COMM` 里的 80 位 IEEE-754 扩展精度浮点解码成 `double`。
///
/// 布局：1 位符号 + 15 位阶码（偏置 16383）+ 64 位尾数（最高位是显式整数位）。
/// 规格表 DSL 没有这个类型，所以 `COMM` 里按 10 字节原样读出，在这里换算。
double decodeExtended80(Uint8List bytes) {
  if (bytes.length < 10) return 0;
  final negative = (bytes[0] & 0x80) != 0;
  final exponent = ((bytes[0] & 0x7F) << 8) | bytes[1];
  var mantissa = 0.0;
  for (var i = 2; i < 10; i++) {
    mantissa = mantissa * 256 + bytes[i];
  }
  if (exponent == 0) {
    // 0 或非规格化数（非规格化数的阶码隐含是 1 - 16383）。
    if (mantissa == 0) return negative ? -0.0 : 0.0;
    final denormal = mantissa * math.pow(2, -16382 - 63).toDouble();
    return negative ? -denormal : denormal;
  }
  if (exponent == 0x7FFF) {
    return mantissa == 0 ? double.infinity : double.nan;
  }
  final value = mantissa * math.pow(2, exponent - 16383 - 63).toDouble();
  return negative ? -value : value;
}

/// WAVEFORMATEXTENSIBLE 扩展部分的解码结果。
typedef WaveFormatExExtension = ({
  /// 有效位数（`wValidBitsPerSample`）。
  int validBits,

  /// 声道掩码（`dwChannelMask`）。
  int channelMask,

  /// 子格式 GUID（`SubFormat`，16 字节）。
  Uint8List subFormat,
});

/// 解码 WAVEFORMATEXTENSIBLE 的扩展部分（`cbSize` 之后那一段）。
///
/// 布局：`wValidBitsPerSample`(u16) + `dwChannelMask`(u32) + `SubFormat`(16 字节 GUID)。
/// 规格表只能表达"定长头 + N 字节扩展"，扩展**内容**在这里手写解码。
WaveFormatExExtension decodeWaveFormatExExtension(Uint8List bytes) {
  if (bytes.length < 22) {
    return (validBits: 0, channelMask: 0, subFormat: Uint8List(0));
  }
  final data = ByteData.sublistView(bytes);
  return (
    validBits: data.getUint16(0, Endian.little),
    channelMask: data.getUint32(2, Endian.little),
    subFormat: Uint8List.fromList(bytes.sublist(6, 22)),
  );
}

// ---------------------------------------------------------------------------
// 叶子提取器
// ---------------------------------------------------------------------------

/// 在结构树里深度优先找第一个类型为 [type] 的块。
ContainerNode? _findChunk(ContainerNode node, String type) {
  for (final child in node.children) {
    if (child.type == type) return child;
    final found = _findChunk(child, type);
    if (found != null) return found;
  }
  return null;
}

/// 节点的字段值表（字段名 → 值）。
Map<String, Object?> _fieldValues(ContainerNode node) {
  return <String, Object?>{
    for (final field in node.fields) field.key: field.value,
  };
}

/// WAV 的叶子提取器：产出统一词表里的音频字段。
///
/// - `sample_rate`（采样率，Hz）、`bit_depth`（位深，bit）、`channels`（声道数）、
///   `codec`（编码标识）取自 `fmt ` 块；`duration`（时长，s）由 `data` 块的长度与
///   `fmt ` 里的 `byte_rate` 算出；`overall_bitrate`（平均码率，bit/s）是推算值。
List<SemanticField> extractWavFields(ContainerNode root) {
  final fields = <SemanticField>[];
  final fmt = _findChunk(root, 'fmt ');
  final data = _findChunk(root, 'data');
  final fmtValues = fmt == null ? const <String, Object?>{} : _fieldValues(fmt);

  final sampleRate = fmtValues['sample_rate'];
  if (sampleRate is int) {
    fields.add(
      SemanticField(
        key: 'sample_rate',
        label: '采样率',
        value: sampleRate,
        unit: 'Hz',
        scope: FieldScope.track,
        trackIndex: 0,
        source: 'fmt ',
      ),
    );
  }

  final bitDepth = fmtValues['bit_depth'];
  if (bitDepth is int) {
    fields.add(
      SemanticField(
        key: 'bit_depth',
        label: '位深',
        value: bitDepth,
        unit: 'bit',
        scope: FieldScope.track,
        trackIndex: 0,
        source: 'fmt ',
      ),
    );
  }

  final channels = fmtValues['channels'];
  if (channels is int) {
    fields.add(
      SemanticField(
        key: 'channels',
        label: '声道数',
        value: channels,
        scope: FieldScope.track,
        trackIndex: 0,
        source: 'fmt ',
      ),
    );
  }

  final codec = fmtValues['wFormatTag'];
  if (codec is int) {
    fields.add(
      SemanticField(
        key: 'codec',
        label: '编码标识',
        value: codec,
        scope: FieldScope.track,
        trackIndex: 0,
        source: 'fmt ',
      ),
    );
  }

  final byteRate = fmtValues['byte_rate'];
  final duration = _duration(data?.dataSize, byteRate);
  if (duration != null) {
    fields.add(
      SemanticField(
        key: 'duration',
        label: '时长',
        value: duration,
        unit: 's',
        scope: FieldScope.file,
        source: 'data',
      ),
    );
    fields.add(
      SemanticField(
        key: 'overall_bitrate',
        label: '平均码率',
        value: (root.size * 8 / duration).round(),
        unit: 'bit/s',
        origin: FieldOrigin.derived,
        scope: FieldScope.file,
        source: 'data',
      ),
    );
  }
  return fields;
}

/// AIFF 的叶子提取器：产出统一词表里的音频字段。
///
/// - `sample_rate`（采样率，Hz）、`bit_depth`（位深，bit）、`channels`（声道数）
///   取自 `COMM` 块；`duration`（时长，s）由 `numSampleFrames` 与采样率算出；
/// - `codec`（编码标识）：AIFF 的 `COMM` 里压缩类型是可选字段，
///   没写就是未压缩（`NONE`），所以它是推算值。
List<SemanticField> extractAiffFields(ContainerNode root) {
  final fields = <SemanticField>[];
  final comm = _findChunk(root, 'COMM');
  final commValues = comm == null
      ? const <String, Object?>{}
      : _fieldValues(comm);

  final rawRate = commValues['sample_rate'];
  final sampleRate = rawRate is Uint8List ? decodeExtended80(rawRate) : null;
  if (sampleRate != null) {
    fields.add(
      SemanticField(
        key: 'sample_rate',
        label: '采样率',
        value: sampleRate.round(),
        unit: 'Hz',
        scope: FieldScope.track,
        trackIndex: 0,
        source: 'COMM',
      ),
    );
  }

  final sampleSize = commValues['sample_size'];
  if (sampleSize is int) {
    fields.add(
      SemanticField(
        key: 'bit_depth',
        label: '位深',
        value: sampleSize,
        unit: 'bit',
        scope: FieldScope.track,
        trackIndex: 0,
        source: 'COMM',
      ),
    );
  }

  final channels = commValues['num_channels'];
  if (channels is int) {
    fields.add(
      SemanticField(
        key: 'channels',
        label: '声道数',
        value: channels,
        scope: FieldScope.track,
        trackIndex: 0,
        source: 'COMM',
      ),
    );
  }

  fields.add(
    const SemanticField(
      key: 'codec',
      label: '编码标识',
      value: 'NONE',
      origin: FieldOrigin.derived,
      scope: FieldScope.track,
      trackIndex: 0,
      source: 'COMM',
    ),
  );

  final frames = commValues['num_sample_frames'];
  if (frames is int && sampleRate != null && sampleRate > 0) {
    final duration = frames / sampleRate;
    fields.add(
      SemanticField(
        key: 'duration',
        label: '时长',
        value: duration,
        unit: 's',
        scope: FieldScope.file,
        source: 'COMM',
      ),
    );
    fields.add(
      SemanticField(
        key: 'overall_bitrate',
        label: '平均码率',
        value: (root.size * 8 / duration).round(),
        unit: 'bit/s',
        origin: FieldOrigin.derived,
        scope: FieldScope.file,
        source: 'COMM',
      ),
    );
  }
  return fields;
}

/// 时长 = 音频数据字节数 ÷ 字节率。算不出来返回 null。
double? _duration(int? dataSize, Object? byteRate) {
  if (dataSize == null) return null;
  if (byteRate is! int || byteRate <= 0) return null;
  return dataSize / byteRate;
}

// ---------------------------------------------------------------------------
// 嗅探与注册
// ---------------------------------------------------------------------------

/// 判断字节源偏移 [offset] 处是不是 ASCII 串 [text]。
bool _hasAscii(ByteSource source, int offset, String text) {
  if (source.length < offset + text.length) return false;
  final bytes = source.read(offset, text.length);
  for (var i = 0; i < text.length; i++) {
    if (bytes[i] != text.codeUnitAt(i)) return false;
  }
  return true;
}

/// WAV 的嗅探：偏移 0 是 `RIFF`，偏移 8 是 `WAVE`。
bool detectWav(ByteSource source) {
  return _hasAscii(source, 0, 'RIFF') && _hasAscii(source, 8, 'WAVE');
}

/// AIFF 的嗅探：偏移 0 是 `FORM`，偏移 8 是 `AIFF`。
bool detectAiff(ByteSource source) {
  return _hasAscii(source, 0, 'FORM') && _hasAscii(source, 8, 'AIFF');
}

/// WAV 格式的注册项。
FormatSpec get wavFormat => FormatSpec(
  name: 'WAV',
  container: wavSpec,
  extractor: extractWavFields,
  detect: detectWav,
  parser: parseWav,
);

/// AIFF 格式的注册项。
FormatSpec get aiffFormat => FormatSpec(
  name: 'AIFF',
  container: aiffSpec,
  extractor: extractAiffFields,
  detect: detectAiff,
  parser: parseAiff,
);

/// 把 WAV 注册进全局格式注册表。
void registerWav() => registerFormat(wavFormat);

/// 把 AIFF 注册进全局格式注册表。
void registerAiff() => registerFormat(aiffFormat);
