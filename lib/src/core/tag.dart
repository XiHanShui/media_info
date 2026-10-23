/// 标签（Tag）——作者写进文件的元数据，与「语义字段」（从容器结构解读出的
/// 技术属性）分开。
///
/// 术语与边界见 `docs/design/core-api.md` §7 与 `.scratch/media-info-mvp/issues/
/// 09-tag-vs-field-boundary.md`：标签单独成区，key **保留英文原名不翻译**
/// （`©nam` 就显示 `©nam`，Vorbis 的 `TITLE` 显示 `TITLE`，ID3 的 `TIT2` 显示
/// `TIT2`）。
///
/// **覆盖的格式**（本 MVP）：
/// - MP4 / MOV：`moov` → `udta` → `meta` → `ilst` 里的 item（`©nam` / `©ART` /
///   `trkn` / `covr` …）；
/// - FLAC：`VORBIS_COMMENT` 块（vendor 串 + `KEY=VALUE` 注释）；
/// - MP3：文件开头的 `ID3v2` 标签（v2.3 / v2.4 的文本帧 `T***`）。
///
/// **节点不持有字节**：载荷（`data` 盒的字节、Vorbis 注释、ID3 帧体）要用
/// [ByteSource] 按偏移现读，所以收集标签需要字节源。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'byte_source.dart';
import 'node.dart';

/// 标签 = 作者写进文件的元数据（与技术属性分开）。
class Tag {
  const Tag({required this.key, this.value, this.source});

  /// 英文原名，不翻译（如 'TITLE'、'ARTIST'）。
  final String key;

  /// 标签值。
  ///
  /// 只有两种形态：
  /// - [String]：文本（标题、艺术家、注释…）；
  /// - [Uint8List]：二进制（`covr` 封面等）。
  final Object? value;

  /// 来自哪个块（如 'ilst'、'VORBIS_COMMENT'）。
  final String? source;

  @override
  String toString() => 'Tag($key: $value)';
}

/// MP4 的标签来源名（`ilst` 盒）。
const String kTagSourceIlst = 'ilst';

/// FLAC 的标签来源名（`VORBIS_COMMENT` 块）。
const String kTagSourceVorbisComment = 'VORBIS_COMMENT';

/// MP3 的标签来源名（`ID3v2` 标签）。
const String kTagSourceId3v2 = 'ID3v2';

/// FLAC Vorbis Comment 里 vendor 串用的 key。
///
/// vendor 串是**编码器**写下的厂商标识（不是用户填的标签），单独成一条是为了
/// 不把它丢掉；界面上可以按 key 过滤掉它。
const String kVorbisVendorKey = 'vendor';

/// 收集一个结构树里的全部标签。
///
/// **按树的形状分派**：遍历树，遇到已知的标签块就按该格式的规则解：
/// - `VORBIS_COMMENT` → FLAC 的 Vorbis Comment；
/// - `ID3v2` → MP3 的 ID3v2 文本帧；
/// - `meta` / `udta` / `moov` / `trak` / `ilst` → MP4 的 `ilst`。
///
/// 其它类型（WAV、Matroska 等没有标签的格式）直接跳过，返回空列表。
///
/// [source] 是文件字节源：**标签载荷需要现读字节**，所以不传字节源就解不出
/// 标签（返回空列表）。想省事可以传 `FileByteSource`。
///
/// **容错**：坏掉的标签区域（长度撒谎、缺字节、编码不认识）一律**跳过**，
/// 不抛异常、不影响同一文件里的其它标签。
List<Tag> collectTags(ContainerNode root, {ByteSource? source}) {
  if (source == null) return const <Tag>[];
  final tags = <Tag>[];
  // MP4 的 `ilst` 可能被多处引用（`moov` 扫描、`udta` 扫描、`meta` 扫描），
  // 按区域起始偏移去重。
  final ilstRegions = <int, _Region>{};

  for (final node in _walk(root)) {
    try {
      switch (node.type) {
        case 'VORBIS_COMMENT':
          tags.addAll(_vorbisCommentTags(node, source));
        case 'ID3v2':
          tags.addAll(_id3v2Tags(node, source));
        case 'meta':
        case 'udta':
        case 'moov':
        case 'trak':
        case 'ilst':
          _collectIlstRegions(node, source, ilstRegions);
      }
    } on Object catch (_) {
      // 一个标签区域坏掉不影响别的：跳过，继续。
    }
  }

  for (final region in ilstRegions.values) {
    try {
      tags.addAll(_ilstTags(region, source));
    } on Object catch (_) {
      // 同上。
    }
  }
  return tags;
}

// ---------------------------------------------------------------------------
// MP4：`moov` → `udta` → `meta` → `ilst`
// ---------------------------------------------------------------------------

/// 一个盒（box）在字节流里的位置。
class _Box {
  const _Box(this.type, this.payloadStart, this.end);

  /// 盒类型（文件里的 4 字节字面名，如 `ilst`、`©nam`）。
  final String type;

  /// 载荷在缓冲里的起始下标。
  final int payloadStart;

  /// 盒的结束下标（不含）。
  final int end;
}

/// 一段 `ilst` 载荷在**文件**里的位置。
class _Region {
  const _Region(this.offset, this.length);

  /// 文件里的起始偏移。
  final int offset;

  /// 载荷字节数。
  final int length;
}

/// 找出这个节点（或它的子树里）所有的 `ilst` 载荷区域。
///
/// 树里的 `meta` 是**不透明叶子**（`ilst` 没被展开），所以这里按字节自己走一遍
/// 盒结构：`udta` → `meta` → `ilst`。`meta` 是 FullBox，载荷开头有 4 字节
/// version/flags。
void _collectIlstRegions(
  ContainerNode node,
  ByteSource source,
  Map<int, _Region> regions,
) {
  final bytes = _readRange(source, node.dataOffset, node.dataSize);
  if (bytes == null || bytes.length < 8) return;
  final base = node.dataOffset;

  if (node.type == 'ilst') {
    // 节点本身就是 `ilst`：载荷就是 item 序列。
    regions.putIfAbsent(base, () => _Region(base, bytes.length));
    return;
  }
  if (node.type == 'meta') {
    // `meta` 是 FullBox：载荷开头 4 字节 version/flags（version 恒为 0）。
    final start = bytes.isNotEmpty && bytes[0] == 0 ? 4 : 0;
    _scanForIlst(bytes, start, bytes.length, base, regions, 0);
    return;
  }
  _scanForIlst(bytes, 0, bytes.length, base, regions, 0);
}

/// 在一段字节里找 `ilst` 盒，只往已知的容器盒里下钻。
void _scanForIlst(
  Uint8List bytes,
  int start,
  int end,
  int base,
  Map<int, _Region> regions,
  int depth,
) {
  if (depth > 4) return;
  for (final box in _boxes(bytes, start, end)) {
    switch (box.type) {
      case 'ilst':
        final offset = base + box.payloadStart;
        regions.putIfAbsent(
          offset,
          () => _Region(offset, box.end - box.payloadStart),
        );
      case 'meta':
        // FullBox：跳过 4 字节 version/flags 再找子盒。
        final skip = box.payloadStart < box.end && bytes[box.payloadStart] == 0
            ? 4
            : 0;
        _scanForIlst(
          bytes,
          box.payloadStart + skip,
          box.end,
          base,
          regions,
          depth + 1,
        );
      case 'udta':
      case 'moov':
      case 'trak':
        _scanForIlst(
          bytes,
          box.payloadStart,
          box.end,
          base,
          regions,
          depth + 1,
        );
    }
  }
}

/// 解一个 `ilst` 载荷区域里的 item。
List<Tag> _ilstTags(_Region region, ByteSource source) {
  final bytes = _readRange(source, region.offset, region.length);
  if (bytes == null || bytes.length < 8) return const <Tag>[];

  final tags = <Tag>[];
  for (final item in _boxes(bytes, 0, bytes.length)) {
    // item 的类型就是标签的 key：`©nam` / `©ART` / `trkn` / `covr` …
    for (final data in _boxes(bytes, item.payloadStart, item.end)) {
      if (data.type != 'data') continue;
      final value = _ilstValue(bytes, data, item.type);
      if (value == null) continue;
      tags.add(Tag(key: item.type, value: value, source: kTagSourceIlst));
    }
  }
  return tags;
}

/// 解一个 `data` 盒的载荷。
///
/// 载荷结构：4 字节 type + 4 字节 locale + 值。
///
/// **type 字段有两种写法**（两种都在野外的文件里出现过）：
/// - 规范写法：1 字节类型码 + 3 字节保留（`01 00 00 00` = UTF-8）；
/// - ffmpeg 写法：4 字节大端整数（`00 00 00 01` = UTF-8）。
///
/// 所以：**首字节是 0 就按 4 字节大端整数读，否则按首字节读**——两种写法都
/// 能解出正确的类型码。
///
/// 类型码：0 = 二进制、1 = UTF-8、2 = UTF-16、13 = JPEG、14 = PNG、
/// 21 = 有符号整数、22 = 无符号整数。类型码不认识时**当二进制**处理，不报错。
Object? _ilstValue(Uint8List bytes, _Box data, String key) {
  if (data.end - data.payloadStart < 8) return null;
  final payload = bytes.sublist(data.payloadStart, data.end);
  final typeCode = payload[0] == 0 ? _u32be(payload, 0) : payload[0];
  final value = payload.sublist(8);

  switch (typeCode) {
    case 1:
      return utf8.decode(value, allowMalformed: true);
    case 2:
      return _decodeUtf16(value);
    case 21:
      return _decodeSignedInt(value);
    case 22:
      return _decodeUnsignedInt(value);
    default:
      // 0（二进制）、13（JPEG）、14（PNG）、27（BMP）以及不认识的类型码。
      // `trkn` 是 iTunes 的定长布局（2 字节填充 + 2 字节曲号 + 2 字节总曲数
      // + 2 字节填充），解成 "曲号/总曲数" 才好读。
      if (key == 'trkn' && value.length == 8) {
        final track = _u16be(value, 2);
        final total = _u16be(value, 4);
        return total > 0 ? '$track/$total' : '$track';
      }
      return Uint8List.fromList(value);
  }
}

/// 有符号整数（`data` 盒类型码 21）→ 十进制字符串。
String? _decodeSignedInt(Uint8List bytes) {
  if (bytes.isEmpty) return null;
  var value = 0;
  for (final byte in bytes) {
    value = (value << 8) | byte;
  }
  final bits = bytes.length * 8;
  if (bits < 64 && (value & (1 << (bits - 1))) != 0) {
    value -= 1 << bits;
  }
  return '$value';
}

/// 无符号整数（`data` 盒类型码 22）→ 十进制字符串。
String? _decodeUnsignedInt(Uint8List bytes) {
  if (bytes.isEmpty) return null;
  var value = 0;
  for (final byte in bytes) {
    value = (value << 8) | byte;
  }
  return '$value';
}

// ---------------------------------------------------------------------------
// FLAC：`VORBIS_COMMENT`
// ---------------------------------------------------------------------------

/// 解 FLAC 的 Vorbis Comment 块。
///
/// 块载荷：vendor 长度（**小端** u32）+ vendor 串 + 注释条数（小端 u32）+
/// 若干条（长度小端 u32 + `KEY=VALUE`）。
List<Tag> _vorbisCommentTags(ContainerNode node, ByteSource source) {
  final bytes = _readRange(source, node.dataOffset, node.dataSize);
  if (bytes == null || bytes.length < 8) return const <Tag>[];

  var pos = 0;
  final vendorLength = _u32le(bytes, pos);
  pos += 4;
  if (vendorLength > bytes.length - pos) return const <Tag>[];
  final vendor = utf8.decode(
    bytes.sublist(pos, pos + vendorLength),
    allowMalformed: true,
  );
  pos += vendorLength;

  if (pos + 4 > bytes.length) return const <Tag>[];
  final count = _u32le(bytes, pos);
  pos += 4;

  final tags = <Tag>[];
  if (vendor.isNotEmpty) {
    tags.add(
      Tag(
        key: kVorbisVendorKey,
        value: vendor,
        source: kTagSourceVorbisComment,
      ),
    );
  }
  for (var i = 0; i < count; i++) {
    if (pos + 4 > bytes.length) break;
    final length = _u32le(bytes, pos);
    pos += 4;
    if (length > bytes.length - pos) break;
    final entry = utf8.decode(
      bytes.sublist(pos, pos + length),
      allowMalformed: true,
    );
    pos += length;
    final separator = entry.indexOf('=');
    // 没有 '=' 或者 key 为空 → 这条不是标签，跳过。
    if (separator <= 0) continue;
    tags.add(
      Tag(
        key: entry.substring(0, separator),
        value: entry.substring(separator + 1),
        source: kTagSourceVorbisComment,
      ),
    );
  }
  return tags;
}

// ---------------------------------------------------------------------------
// MP3：`ID3v2`
// ---------------------------------------------------------------------------

/// 解 ID3v2 标签里的文本帧（`T***`）。
///
/// 只支持 v2.3 / v2.4：v2.3 的帧大小是普通整数，v2.4 是 syncsafe 整数。
/// 非文本帧、压缩帧、加密帧一律跳过。
List<Tag> _id3v2Tags(ContainerNode node, ByteSource source) {
  final header = _readRange(source, node.offset, 10);
  if (header == null || header.length < 10) return const <Tag>[];
  if (header[0] != 0x49 || header[1] != 0x44 || header[2] != 0x33) {
    return const <Tag>[];
  }
  final major = header[3];
  final flags = header[5];
  if (major != 3 && major != 4) return const <Tag>[];

  var payload = _readRange(source, node.dataOffset, node.dataSize);
  if (payload == null || payload.isEmpty) return const <Tag>[];
  // 标签级反同步：整块数据里的 0xFF 0x00 要还原成 0xFF。
  if ((flags & 0x80) != 0) payload = _deUnsync(payload);

  var pos = 0;
  if ((flags & 0x40) != 0) {
    // 扩展头：v2.3 的长度不含自身，v2.4 的长度含自身。
    if (payload.length < 4) return const <Tag>[];
    final declared = major == 4 ? _syncsafe(payload, 0) : _u32be(payload, 0);
    pos = major == 4 ? declared : 4 + declared;
    if (pos < 0 || pos > payload.length) return const <Tag>[];
  }

  final tags = <Tag>[];
  final end = payload.length;
  while (pos + 10 <= end) {
    final id = String.fromCharCodes(payload.sublist(pos, pos + 4));
    // 帧 ID 全 0 或含非法字符 → 后面是填充，结束。
    if (id.codeUnitAt(0) == 0 || !_isFrameId(id)) break;
    final size = major == 4
        ? _syncsafe(payload, pos + 4)
        : _u32be(payload, pos + 4);
    final frameFlags = _u16be(payload, pos + 8);

    var bodyStart = pos + 10;
    var bodyLength = size;
    // v2.4 的「数据长度指示符」占帧体开头 4 字节。
    if (major == 4 && (frameFlags & 0x0001) != 0) {
      bodyStart += 4;
      bodyLength -= 4;
    }
    if (bodyLength < 0) break;
    // 帧体被截断：裁到实际有的字节。
    if (bodyStart + bodyLength > end) bodyLength = end - bodyStart;
    if (bodyLength <= 0) break;

    final compressed = major == 4
        ? (frameFlags & 0x0004) != 0
        : (frameFlags & 0x0080) != 0;
    final encrypted = major == 4
        ? (frameFlags & 0x0002) != 0
        : (frameFlags & 0x0040) != 0;
    if (!compressed && !encrypted && _isTextFrameId(id)) {
      final value = _decodeId3Text(
        payload.sublist(bodyStart, bodyStart + bodyLength),
      );
      if (value != null) {
        tags.add(Tag(key: id, value: value, source: kTagSourceId3v2));
      }
    }
    pos = bodyStart + bodyLength;
  }
  return tags;
}

/// 帧 ID 是否合法（4 个大写字母或数字）。
bool _isFrameId(String id) {
  for (final unit in id.codeUnits) {
    final isUpper = unit >= 0x41 && unit <= 0x5A;
    final isDigit = unit >= 0x30 && unit <= 0x39;
    if (!isUpper && !isDigit) return false;
  }
  return true;
}

/// `T***`（除 `TXXX`）是文本帧。
bool _isTextFrameId(String id) =>
    id.length == 4 && id.startsWith('T') && id != 'TXXX';

/// 解 ID3 文本帧的帧体：1 字节编码 + 文本。
///
/// 编码：0 = ISO-8859-1、1 = UTF-16（带 BOM）、2 = UTF-16BE、3 = UTF-8。
String? _decodeId3Text(Uint8List body) {
  if (body.isEmpty) return null;
  final encoding = body[0];
  var data = body.sublist(1);
  // 文本帧以 NUL 结尾。
  var length = data.length;
  while (length > 0 && data[length - 1] == 0) {
    length--;
  }
  data = data.sublist(0, length);

  switch (encoding) {
    case 0:
      return latin1.decode(data);
    case 1:
      return _decodeUtf16(data);
    case 2:
      return _decodeUtf16(data, endian: Endian.big);
    case 3:
      return utf8.decode(data, allowMalformed: true);
    default:
      // 不认识的编码 → 当 UTF-8 试一次，解不出来也不报错。
      return utf8.decode(data, allowMalformed: true);
  }
}

// ---------------------------------------------------------------------------
// 通用工具
// ---------------------------------------------------------------------------

/// 深度优先遍历结构树。
Iterable<ContainerNode> _walk(ContainerNode node) sync* {
  yield node;
  for (final child in node.children) {
    yield* _walk(child);
  }
}

/// 读一段字节；越界或读失败返回 null（不抛异常）。
Uint8List? _readRange(ByteSource source, int offset, int length) {
  if (offset < 0 || length <= 0) return null;
  final available = source.length - offset;
  if (available <= 0) return null;
  final count = length < available ? length : available;
  try {
    return source.read(offset, count);
  } on Object catch (_) {
    return null;
  }
}

/// 迭代一段字节里的盒（ISO BMFF 风格：4 字节大小 + 4 字节类型 + 载荷）。
///
/// 长度撒谎的盒会被裁到可用范围；遇到非法长度就停止迭代。
Iterable<_Box> _boxes(Uint8List bytes, int start, int end) sync* {
  var pos = start;
  final limit = end < bytes.length ? end : bytes.length;
  while (pos + 8 <= limit) {
    var size = _u32be(bytes, pos);
    var headerSize = 8;
    if (size == 1) {
      if (pos + 16 > limit) break;
      size = _u64be(bytes, pos + 8);
      headerSize = 16;
    } else if (size == 0) {
      size = limit - pos;
    }
    if (size < headerSize) break;
    var boxEnd = pos + size;
    if (boxEnd > limit) boxEnd = limit;
    if (boxEnd <= pos) break;
    final type = String.fromCharCodes(bytes.sublist(pos + 4, pos + 8));
    yield _Box(type, pos + headerSize, boxEnd);
    pos = boxEnd;
  }
}

/// 大端 16 位。
int _u16be(Uint8List bytes, int offset) =>
    (bytes[offset] << 8) | bytes[offset + 1];

/// 大端 32 位。
int _u32be(Uint8List bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

/// 小端 32 位。
int _u32le(Uint8List bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

/// 大端 64 位。
int _u64be(Uint8List bytes, int offset) {
  var value = 0;
  for (var i = 0; i < 8; i++) {
    value = (value << 8) | bytes[offset + i];
  }
  return value;
}

/// syncsafe 整数（每字节只用 7 位，ID3v2 的长度字段）。
int _syncsafe(Uint8List bytes, int offset) =>
    ((bytes[offset] & 0x7F) << 21) |
    ((bytes[offset + 1] & 0x7F) << 14) |
    ((bytes[offset + 2] & 0x7F) << 7) |
    (bytes[offset + 3] & 0x7F);

/// 解 UTF-16 文本（BOM 决定字节序，没有 BOM 按大端）。
String _decodeUtf16(Uint8List bytes, {Endian endian = Endian.big}) {
  var start = 0;
  var order = endian;
  if (bytes.length >= 2) {
    if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
      order = Endian.little;
      start = 2;
    } else if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
      order = Endian.big;
      start = 2;
    }
  }
  final data = ByteData.sublistView(Uint8List.fromList(bytes.sublist(start)));
  final buffer = StringBuffer();
  for (var i = 0; i + 1 < bytes.length - start; i += 2) {
    buffer.writeCharCode(data.getUint16(i, order));
  }
  return buffer.toString();
}

/// 还原 ID3 的反同步（0xFF 0x00 → 0xFF）。
Uint8List _deUnsync(Uint8List bytes) {
  final out = <int>[];
  for (var i = 0; i < bytes.length; i++) {
    out.add(bytes[i]);
    if (bytes[i] == 0xFF && i + 1 < bytes.length && bytes[i + 1] == 0) {
      i++;
    }
  }
  return Uint8List.fromList(out);
}
