/// MP3：帧序列解析 + 叶子提取器。
///
/// **MP3 没有真正的块树**——它是连续的帧序列，帧长不是文件里写着的，而是由帧头里的
/// 码率与采样率算出来的。通用容器引擎的「类型 + 长度」块头规则表达不了它，
/// 所以本文件里的解析器是**手写**的：直接产出核心层的 [ContainerNode] / [SemanticField]。
///
/// 结构树长这样：
///
/// ```
/// MP3（根节点，整个文件）
///  ├─ ID3v2（文件开头的标签，记录偏移与大小）
///  ├─ MPEG Audio Frame（帧 1，带自己的帧头字段）
///  ├─ MPEG Audio Frame（帧 2）
///  └─ …
/// ```
///
/// 解析入口是 [parseMp3]；**不要**用 [parseContainer] 解析 MP3（那张规格表只是占位，
/// 用来满足 [FormatSpec] 的接口形状）。
library;

import 'dart:typed_data';

import '../core/byte_source.dart';
import '../core/engine.dart';
import '../core/node.dart';
import '../core/registry.dart';
import '../core/spec.dart';

/// 帧节点在结构树里的类型名。
const String kMp3FrameType = 'MPEG Audio Frame';

/// 同步字校验失败、无法解析成帧的那段数据在结构树里的类型名。
const String kMp3InvalidFrameType = 'Invalid Frame';

/// 文件开头的 ID3v2 标签节点在结构树里的类型名。
const String kMp3Id3v2Type = 'ID3v2';

/// MP3 的容器规格表——**占位**。
///
/// 帧长是算出来的（`floor(每帧采样数 ÷ 采样率 × 码率 ÷ 8) + 填充`），通用容器引擎的
/// 块头规则里没有「长度由字段算出」这种读法，所以这张表表达不了 MP3 的帧序列。
/// 真正的解析走 [parseMp3]；这里保留它只是为了满足 [FormatSpec] 的接口形状
/// （注册表登记的是规格表 + 提取器，不是解析器对象）。
const ContainerSpec _mp3Container = ContainerSpec(
  name: 'MP3',
  header: HeaderRule(typeBytes: 0, sizeBytes: 0),
  children: <String, ChildSpec>{},
);

/// MP3 格式规格（规格表 + 叶子提取器 + 嗅探回调）。
///
/// **解析 MP3 请用 [parseMp3]，不要用 [parseContainer]**：MP3 的帧长是算出来的，
/// 通用容器引擎的规格表表达不了它，这里的 [FormatSpec.container] 只是占位。
FormatSpec get mp3Format => FormatSpec(
  name: 'MP3',
  container: _mp3Container,
  extractor: extractMp3Fields,
  detect: detectMp3,
);

/// 注册 MP3 格式。重复注册安全（同名格式会被替换而不是重复登记）。
///
/// 本文件**不在 import 时做注册**——注册由调用方显式触发。
void registerMp3() => registerFormat(mp3Format);

/// 嗅探：只看文件头，不看扩展名。
///
/// - 偏移 0 是 `ID3`（ID3v2 标签）→ 是 MP3；
/// - 偏移 0 是合法的 MPEG 音频帧同步字（`0xFF Ex/Fx`）→ 是 MP3。
bool detectMp3(ByteSource source) {
  final length = source.length;
  if (length >= 3) {
    final head = source.read(0, 3);
    if (head[0] == 0x49 && head[1] == 0x44 && head[2] == 0x33) return true;
  }
  if (length >= 4) {
    return _isFrameHeader(source.read(0, 4), 0);
  }
  return false;
}

/// 叶子提取器：从已解析的树里取统一词表的语义字段（不重复解析字节）。
///
/// MP3 只有一条音轨，所以轨道级字段挂在根节点上（[FieldScope.track]，[trackIndex] 0）。
List<SemanticField> extractMp3Fields(ContainerNode root) => root.fields
    .where((f) => _unifiedKeys.contains(f.key))
    .toList(growable: false);

/// 统一词表里 MP3 会产出的键。
const Set<String> _unifiedKeys = <String>{
  'duration',
  'overall_bitrate',
  'codec',
  'sample_rate',
  'channels',
};

/// 解析一个 MP3 文件，产出结构树。
///
/// [depth] 保留是为了和 [parseContainer] 的签名对称：MP3 的树只有两层
/// （根节点 → 帧节点），帧节点没有子节点，所以 `depth >= 1` 时帧列表总是完整的。
///
/// 引擎的约定在这里同样成立：**不抛异常**，截断时 `truncated == true` 且 `error`
/// 给出中文说明，已解析的部分照常返回。
ParseResult parseMp3(ByteSource source, {int depth = 1}) {
  final length = source.length;
  final children = <ContainerNode>[];
  final problems = <String>[];
  var truncated = false;

  var pos = 0;

  // --- 文件开头的 ID3v2 标签：跳过，但记下它的偏移与大小 ---
  if (length >= 10 && _hasId3v2Header(source)) {
    final header = _readId3v2Header(source);
    final hasFooter = (header.flags & 0x10) != 0;
    final declared = 10 + header.size + (hasFooter ? 10 : 0);
    if (declared > length) {
      truncated = true;
      problems.add('文件在偏移 $length 处截断，ID3v2 标签声明长度还差 ${declared - length} 字节');
      children.add(
        ContainerNode(
          type: kMp3Id3v2Type,
          offset: 0,
          size: length,
          dataOffset: 10,
          dataSize: length - 10,
          isOpaque: true,
          fields: _id3v2Fields(header),
        ),
      );
      pos = length;
    } else {
      children.add(
        ContainerNode(
          type: kMp3Id3v2Type,
          offset: 0,
          size: declared,
          dataOffset: 10,
          dataSize: header.size,
          fields: _id3v2Fields(header),
        ),
      );
      pos = declared;
    }
  }

  // --- 帧序列 ---
  final entries = <_Entry>[];
  while (pos < length) {
    if (length - pos < 4) {
      truncated = true;
      problems.add('文件在偏移 $pos 处截断，帧头不完整');
      entries.add(_BadEntry(pos, length - pos, '帧头不完整：只剩 ${length - pos} 字节'));
      break;
    }
    final header = _readFrameHeader(source, pos);
    if (header == null) {
      // 坏帧不终止解析：标记出来，然后往后找下一个同步字继续。
      final next = _findNextFrame(source, pos + 1, length);
      final end = next ?? length;
      entries.add(_BadEntry(pos, end - pos, '帧同步字校验失败'));
      if (next == null) break;
      pos = next;
      continue;
    }
    final available = length - pos;
    if (header.frameLength > available) {
      // 帧被截断：留在树里，长度裁剪到实际有的字节。
      truncated = true;
      problems.add(
        '文件在偏移 $pos 处截断，帧声明长度还差 ${header.frameLength - available} 字节',
      );
      entries.add(_FrameEntry(header, available, truncated: true));
      break;
    }
    entries.add(_FrameEntry(header, header.frameLength, truncated: false));
    pos += header.frameLength;
  }

  // --- 码率模式：所有帧码率一样就是 CBR，否则是 VBR ---
  final bitrates = <int>{
    for (final entry in entries)
      if (entry is _FrameEntry && !entry.truncated) entry.header.bitrate,
  };
  final bitrateMode = bitrates.length <= 1 ? 'CBR' : 'VBR';

  for (final entry in entries) {
    switch (entry) {
      case _BadEntry():
        children.add(
          ContainerNode(
            type: kMp3InvalidFrameType,
            offset: entry.offset,
            size: entry.size,
            dataOffset: entry.offset,
            dataSize: entry.size,
            isOpaque: true,
            fields: [
              SemanticField(
                key: 'parse_error',
                label: '解析错误',
                value: entry.reason,
                source: kMp3FrameType,
              ),
            ],
          ),
        );
      case _FrameEntry():
        final header = entry.header;
        children.add(
          ContainerNode(
            type: kMp3FrameType,
            offset: header.offset,
            size: entry.size,
            dataOffset: header.offset + 4,
            dataSize: entry.size > 4 ? entry.size - 4 : 0,
            isOpaque: entry.truncated,
            fields: _frameFields(header, bitrateMode),
          ),
        );
    }
  }

  // --- 语义字段（文件级 + 轨道级，都挂在根节点上：MP3 只有一条音轨）---
  final frames = entries.whereType<_FrameEntry>().toList();
  final complete = frames.where((f) => !f.truncated).toList();
  final first = complete.isEmpty
      ? (frames.isEmpty ? null : frames.first)
      : complete.first;

  var duration = 0.0;
  if (first != null) {
    duration =
        complete.length *
        first.header.samplesPerFrame /
        first.header.sampleRate;
  }

  final rootFields = <SemanticField>[
    SemanticField(
      key: 'duration',
      label: '时长',
      value: duration,
      unit: 's',
      source: kMp3FrameType,
    ),
  ];
  if (duration > 0) {
    rootFields.add(
      SemanticField(
        key: 'overall_bitrate',
        label: '平均码率',
        value: (length * 8 / duration).round(),
        unit: 'bit/s',
        origin: FieldOrigin.derived,
        source: kMp3FrameType,
      ),
    );
  }
  if (first != null) {
    rootFields.addAll([
      SemanticField(
        key: 'codec',
        label: '编码标识',
        value: _codecName(first.header),
        scope: FieldScope.track,
        trackIndex: 0,
        source: kMp3FrameType,
      ),
      SemanticField(
        key: 'sample_rate',
        label: '采样率',
        value: first.header.sampleRate,
        unit: 'Hz',
        scope: FieldScope.track,
        trackIndex: 0,
        source: kMp3FrameType,
      ),
      SemanticField(
        key: 'channels',
        label: '声道数',
        value: _channelCount(first.header.channelMode),
        scope: FieldScope.track,
        trackIndex: 0,
        source: kMp3FrameType,
      ),
    ]);
  }

  final root = ContainerNode(
    type: 'MP3',
    offset: 0,
    size: length,
    dataOffset: 0,
    dataSize: length,
    children: children,
    fields: rootFields,
  );

  return ParseResult(
    root: root,
    truncated: truncated,
    error: problems.isEmpty ? null : problems.join('；'),
  );
}

/// codec 标识：由版本与层组合而成，如 `MPEG-1 Layer 3`。
String _codecName(_FrameHeader header) =>
    '${_mpegVersionName(header.mpegVersion)} Layer ${header.layer}';

/// MPEG 版本名：帧头里的 2 bit 版本号 → `MPEG-1` / `MPEG-2` / `MPEG-2.5`。
String _mpegVersionName(int version) => switch (version) {
  3 => 'MPEG-1',
  2 => 'MPEG-2',
  _ => 'MPEG-2.5',
};

/// 声道模式名：帧头里的 2 bit 声道模式。
const List<String> _channelModeNames = <String>[
  'Stereo',
  'Joint Stereo',
  'Dual Channel',
  'Mono',
];

/// 声道模式 → 声道数（单声道 1，其余 2）。
int _channelCount(int channelMode) => channelMode == 3 ? 1 : 2;

/// 帧节点的字段：这一帧自己的帧头信息 + 格式特有字段。
List<SemanticField> _frameFields(_FrameHeader header, String bitrateMode) => [
  SemanticField(
    key: 'mpeg_version',
    label: 'MPEG 版本',
    value: _mpegVersionName(header.mpegVersion),
    source: kMp3FrameType,
  ),
  SemanticField(
    key: 'layer',
    label: '层',
    value: header.layer,
    source: kMp3FrameType,
  ),
  SemanticField(
    key: 'bitrate',
    label: '码率',
    value: header.bitrate,
    unit: 'kbps',
    source: kMp3FrameType,
  ),
  SemanticField(
    key: 'bitrate_mode',
    label: '码率模式',
    value: bitrateMode,
    source: kMp3FrameType,
  ),
  SemanticField(
    key: 'sample_rate',
    label: '采样率',
    value: header.sampleRate,
    unit: 'Hz',
    scope: FieldScope.track,
    trackIndex: 0,
    source: kMp3FrameType,
  ),
  SemanticField(
    key: 'channel_mode',
    label: '声道模式',
    value: _channelModeNames[header.channelMode],
    source: kMp3FrameType,
  ),
  SemanticField(
    key: 'padding',
    label: '填充字节',
    value: header.padding,
    unit: 'byte',
    source: kMp3FrameType,
  ),
  SemanticField(
    key: 'samples_per_frame',
    label: '每帧采样数',
    value: header.samplesPerFrame,
    source: kMp3FrameType,
  ),
  SemanticField(
    key: 'frame_length',
    label: '帧长度',
    value: header.frameLength,
    unit: 'byte',
    source: kMp3FrameType,
  ),
  SemanticField(
    key: 'crc_protected',
    label: 'CRC 校验',
    value: header.crcProtected,
    source: kMp3FrameType,
  ),
];

/// ID3v2 标签节点的字段。
List<SemanticField> _id3v2Fields(_Id3v2Header header) => [
  SemanticField(
    key: 'id3v2_version',
    label: 'ID3v2 版本',
    value: '${header.versionMajor}.${header.versionMinor}',
    source: kMp3Id3v2Type,
  ),
  SemanticField(
    key: 'id3v2_flags',
    label: 'ID3v2 标志',
    value: header.flags,
    source: kMp3Id3v2Type,
  ),
];

// ---------------------------------------------------------------------------
// 内部实现
// ---------------------------------------------------------------------------

/// 帧序列里的一个条目：要么是一帧，要么是一段解析不了的数据。
sealed class _Entry {
  const _Entry();
}

/// 一帧。[size] 是它在文件里实际占的字节数（被截断时小于声明长度）。
final class _FrameEntry extends _Entry {
  const _FrameEntry(this.header, this.size, {required this.truncated});

  final _FrameHeader header;
  final int size;
  final bool truncated;
}

/// 一段解析不了的数据。
final class _BadEntry extends _Entry {
  const _BadEntry(this.offset, this.size, this.reason);

  final int offset;
  final int size;
  final String reason;
}

/// 一个 MPEG 音频帧的头。
class _FrameHeader {
  const _FrameHeader({
    required this.offset,
    required this.mpegVersion,
    required this.layer,
    required this.crcProtected,
    required this.bitrate,
    required this.sampleRate,
    required this.padding,
    required this.channelMode,
    required this.samplesPerFrame,
    required this.frameLength,
  });

  /// 帧在文件里的偏移。
  final int offset;

  /// MPEG 版本号：3 = MPEG-1，2 = MPEG-2，0 = MPEG-2.5（1 是保留值）。
  final int mpegVersion;

  /// 层号：1 = Layer III，2 = Layer II，3 = Layer I（0 是保留值）。
  final int layer;

  /// 有 CRC 校验（protection bit 为 0）。
  final bool crcProtected;

  /// 码率（kbps）。
  final int bitrate;

  /// 采样率（Hz）。
  final int sampleRate;

  /// 填充字节数（0 或 1）。
  final int padding;

  /// 声道模式：0 = Stereo，1 = Joint Stereo，2 = Dual Channel，3 = Mono。
  final int channelMode;

  /// 每帧的采样数。
  final int samplesPerFrame;

  /// 帧总长度（字节，含 4 字节帧头）。
  final int frameLength;
}

/// ID3v2 标签头。
class _Id3v2Header {
  const _Id3v2Header({
    required this.versionMajor,
    required this.versionMinor,
    required this.flags,
    required this.size,
  });

  final int versionMajor;
  final int versionMinor;
  final int flags;

  /// 标签载荷大小（syncsafe 整数，不含 10 字节的头）。
  final int size;
}

/// MPEG-1 的码率表（kbps），下标 = 码率索引（0 = free，15 = 无效）。
const Map<int, List<int>> _mpeg1Bitrates = <int, List<int>>{
  1: <int>[
    0,
    32,
    64,
    96,
    128,
    160,
    192,
    224,
    256,
    288,
    320,
    352,
    384,
    416,
    448,
  ],
  2: <int>[0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384],
  3: <int>[0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320],
};

/// MPEG-2 / MPEG-2.5 的码率表（kbps）。
const Map<int, List<int>> _mpeg2Bitrates = <int, List<int>>{
  1: <int>[0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256],
  2: <int>[0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
  3: <int>[0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
};

/// MPEG-1 的采样率表（Hz）。
const List<int> _mpeg1SampleRates = <int>[44100, 48000, 32000];

/// MPEG-2 的采样率表（Hz）。
const List<int> _mpeg2SampleRates = <int>[22050, 24000, 16000];

/// MPEG-2.5 的采样率表（Hz）。
const List<int> _mpeg25SampleRates = <int>[11025, 12000, 8000];

/// 帧头里的 2 bit 层号 → 层号（1 = Layer I，2 = Layer II，3 = Layer III）。
///
/// 帧头里的编码是 `01` = Layer III、`10` = Layer II、`11` = Layer I——和「层号」正好相反。
int _layerNumber(int code) => switch (code) {
  1 => 3,
  2 => 2,
  _ => 1,
};

/// 每帧采样数。
int _samplesPerFrame(int mpegVersion, int layer) {
  if (layer == 1) return 384; // Layer I 恒定 384
  if (mpegVersion == 3) return 1152; // MPEG-1 的 Layer II / III
  return layer == 3 ? 576 : 1152; // MPEG-2 / 2.5：Layer III 是 576
}

/// 采样率表（按 MPEG 版本取）。
List<int> _sampleRates(int mpegVersion) => switch (mpegVersion) {
  3 => _mpeg1SampleRates,
  2 => _mpeg2SampleRates,
  _ => _mpeg25SampleRates,
};

/// 码率表（按 MPEG 版本取）。
Map<int, List<int>> _bitrates(int mpegVersion) =>
    mpegVersion == 3 ? _mpeg1Bitrates : _mpeg2Bitrates;

/// 文件开头是不是 ID3v2 标签。
bool _hasId3v2Header(ByteSource source) {
  final head = source.read(0, 3);
  return head[0] == 0x49 && head[1] == 0x44 && head[2] == 0x33;
}

/// 读 ID3v2 标签头（10 字节）。
_Id3v2Header _readId3v2Header(ByteSource source) {
  final raw = source.read(0, 10);
  final size =
      ((raw[6] & 0x7F) << 21) |
      ((raw[7] & 0x7F) << 14) |
      ((raw[8] & 0x7F) << 7) |
      (raw[9] & 0x7F);
  return _Id3v2Header(
    versionMajor: raw[3],
    versionMinor: raw[4],
    flags: raw[5],
    size: size,
  );
}

/// 判断这 4 个字节是不是一个合法的帧头（同步字 + 版本 / 层 / 码率 / 采样率索引）。
bool _isFrameHeader(Uint8List bytes, int index) {
  if (bytes[index] != 0xFF) return false;
  if ((bytes[index + 1] & 0xE0) != 0xE0) return false; // 11 bit 同步字
  final version = (bytes[index + 1] >> 3) & 0x03;
  if (version == 1) return false; // 保留的版本号
  final layer = (bytes[index + 1] >> 1) & 0x03;
  if (layer == 0) return false; // 保留的层号
  final bitrateIndex = (bytes[index + 2] >> 4) & 0x0F;
  if (bitrateIndex == 0 || bitrateIndex == 15) return false;
  final sampleRateIndex = (bytes[index + 2] >> 2) & 0x03;
  if (sampleRateIndex == 3) return false; // 保留的采样率索引
  return true;
}

/// 读一个帧头。返回 null 表示这里不是一个合法的帧头。
_FrameHeader? _readFrameHeader(ByteSource source, int offset) {
  final raw = source.read(offset, 4);
  if (!_isFrameHeader(raw, 0)) return null;

  final version = (raw[1] >> 3) & 0x03;
  final layer = _layerNumber((raw[1] >> 1) & 0x03);
  final crcProtected = (raw[1] & 0x01) == 0;
  final bitrateIndex = (raw[2] >> 4) & 0x0F;
  final sampleRateIndex = (raw[2] >> 2) & 0x03;
  final padding = (raw[2] >> 1) & 0x01;
  final channelMode = (raw[3] >> 6) & 0x03;

  final bitrate = _bitrates(version)[layer]![bitrateIndex];
  final sampleRate = _sampleRates(version)[sampleRateIndex];
  final samples = _samplesPerFrame(version, layer);
  // 帧长 = floor(每帧采样数 ÷ 采样率 × 码率 ÷ 8) + 填充
  final frameLength = (samples * bitrate * 1000) ~/ (sampleRate * 8) + padding;

  return _FrameHeader(
    offset: offset,
    mpegVersion: version,
    layer: layer,
    crcProtected: crcProtected,
    bitrate: bitrate,
    sampleRate: sampleRate,
    padding: padding,
    channelMode: channelMode,
    samplesPerFrame: samples,
    frameLength: frameLength,
  );
}

/// 从 [from] 开始往后找下一个合法帧头的位置；找不到返回 null。
int? _findNextFrame(ByteSource source, int from, int length) {
  if (from >= length) return null;
  const chunkSize = 4096;
  var pos = from;
  while (pos < length) {
    final end = pos + chunkSize < length ? pos + chunkSize : length;
    final data = source.read(pos, end - pos);
    for (var i = 0; i + 3 < data.length; i++) {
      if (data[i] != 0xFF) continue;
      if ((data[i + 1] & 0xE0) != 0xE0) continue;
      if (_isFrameHeader(data, i)) return pos + i;
    }
    if (end == length) break;
    // 回退 3 字节，覆盖跨块边界的帧头。
    pos = end - 3;
    if (pos < from) pos = from;
  }
  return null;
}
