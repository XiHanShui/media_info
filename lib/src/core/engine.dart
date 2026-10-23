import 'dart:convert';
import 'dart:typed_data';

import 'byte_source.dart';
import 'node.dart';
import 'spec.dart';

/// 递归深度上限（防止规格表成环导致无限递归）。
const int kMaxRecursionDepth = 64;

/// 解析结果。
class ParseResult {
  const ParseResult({required this.root, this.truncated = false, this.error});

  /// 结构树的根节点。
  final ContainerNode root;

  /// 文件被截断。
  final bool truncated;

  /// 面向用户的中文错误说明。
  final String? error;
}

/// 解析一个容器。
///
/// [depth] 控制惰性展开：展开的层数（根节点的子块是第 1 层）。
/// - `depth: 1`（默认）只建根节点的第一层子块；
/// - `depth: 2` 再建第二层；
/// - `depth <= 0` 按第一层处理。
///
/// 更深的层可以在需要时用更大的 [depth] 重新解析（重新读字节，不缓存）。
///
/// [maxDepth] 是结构递归上限（防环），默认 [kMaxRecursionDepth]；
/// 超过上限的块不再展开，并被标记为不透明。
///
/// 引擎**不抛异常**给 UI 层：读到的字节少于声明长度时立即停止，
/// 结果里 `truncated == true` 且 `error` 给出中文说明，已解析的部分照常返回。
ParseResult parseContainer(
  ContainerSpec spec,
  ByteSource source, {
  int depth = 1,
  int maxDepth = kMaxRecursionDepth,
}) {
  final ctx = _ParseContext(source, maxDepth);
  final levels = depth < 1 ? 1 : depth;
  final scopes = <_Scope>[_Scope(spec.children, const <String, Object?>{})];
  final children = _parseChildren(
    ctx: ctx,
    container: spec,
    start: 0,
    end: source.length,
    level: 1,
    levels: levels,
    scopes: scopes,
  );
  final root = ContainerNode(
    type: spec.effectiveRootType,
    offset: 0,
    size: source.length,
    dataOffset: 0,
    dataSize: source.length,
    children: children,
  );
  return ParseResult(root: root, truncated: ctx.truncated, error: ctx.error);
}

// ---------------------------------------------------------------------------
// 内部实现
// ---------------------------------------------------------------------------

class _ParseContext {
  _ParseContext(this.source, this.maxDepth);

  final ByteSource source;
  final int maxDepth;
  bool truncated = false;
  String? error;

  /// 记录第一次错误（后续错误不覆盖）。
  void report(String message) {
    truncated = true;
    error ??= message;
  }
}

/// 一层作用域：容器的 children 表 + 从祖先继承下来的字段值。
class _Scope {
  const _Scope(this.children, this.values);

  final Map<String, ChildSpec> children;
  final Map<String, Object?> values;
}

class _ChunkOutcome {
  const _ChunkOutcome({
    required this.node,
    required this.next,
    this.stop = false,
  });

  final ContainerNode node;
  final int next;
  final bool stop;
}

/// 字段读数越界（块载荷里没有那么多字节）。
class _FieldOverrun implements Exception {
  _FieldOverrun(this.offset, this.fieldName);

  final int offset;
  final String fieldName;
}

List<ContainerNode> _parseChildren({
  required _ParseContext ctx,
  required ContainerSpec container,
  required int start,
  required int end,
  required int level,
  required int levels,
  required List<_Scope> scopes,
}) {
  if (level > levels) return const <ContainerNode>[];
  final limit = end < ctx.source.length ? end : ctx.source.length;
  final nodes = <ContainerNode>[];
  var pos = start;
  while (pos < limit) {
    final outcome = _parseChunk(
      ctx: ctx,
      container: container,
      pos: pos,
      regionEnd: end,
      limit: limit,
      level: level,
      levels: levels,
      scopes: scopes,
    );
    if (outcome == null) break;
    nodes.add(outcome.node);
    if (outcome.stop) break;
    if (outcome.next <= pos) break; // 没有前进，避免死循环
    pos = outcome.next;
  }
  return nodes;
}

_ChunkOutcome? _parseChunk({
  required _ParseContext ctx,
  required ContainerSpec container,
  required int pos,
  required int regionEnd,
  required int limit,
  required int level,
  required int levels,
  required List<_Scope> scopes,
}) {
  final rule = container.header;

  // --- 块头：类型字段与长度字段（顺序由 rule.sizeFirst 决定） ---
  String type = '';
  var typeLen = 0;
  var sizeLen = 0;
  int? declaredSize;
  var sizeUnknown = false;

  bool readType(int at) {
    if (rule.vintId) {
      final width = _vintWidthAt(ctx.source, at, limit);
      if (width <= 0) {
        ctx.report('文件在偏移 $at 处无法解析变长类型');
        return false;
      }
      if (at + width > limit) {
        ctx.report('文件在偏移 $at 处截断，块类型不完整');
        return false;
      }
      type = '0x${_toHex(ctx.source.read(at, width))}';
      typeLen = width;
      return true;
    }
    if (rule.typeBytes <= 0) {
      type = '';
      typeLen = 0;
      return true;
    }
    if (at + rule.typeBytes > limit) {
      ctx.report('文件在偏移 $at 处截断，块类型不完整');
      return false;
    }
    type = String.fromCharCodes(ctx.source.read(at, rule.typeBytes));
    typeLen = rule.typeBytes;
    return true;
  }

  bool readSize(int at) {
    if (rule.vintSize) {
      final width = _vintWidthAt(ctx.source, at, limit);
      if (width <= 0) {
        ctx.report('文件在偏移 $at 处无法解析变长长度');
        return false;
      }
      if (at + width > limit) {
        ctx.report('文件在偏移 $at 处截断，长度字段不完整');
        return false;
      }
      final decoded = _decodeVint(ctx.source.read(at, width));
      sizeLen = width;
      if (rule.unknownSizeAllowed &&
          decoded.value == _vintMaxValue(decoded.width)) {
        sizeUnknown = true;
      } else {
        declaredSize = decoded.value;
      }
      return true;
    }
    if (rule.sizeBytes <= 0) {
      // 没有长度字段：载荷一直到区域末尾。
      sizeLen = 0;
      declaredSize = null;
      return true;
    }
    if (at + rule.sizeBytes > limit) {
      ctx.report('文件在偏移 $at 处截断，长度字段不完整');
      return false;
    }
    final raw = ctx.source.read(at, rule.sizeBytes);
    final size = _readUintBytes(raw, rule.endian);
    sizeLen = rule.sizeBytes;
    if (rule.unknownSizeAllowed && _isAllOnes(raw)) {
      sizeUnknown = true;
    } else {
      declaredSize = size;
    }
    return true;
  }

  if (rule.sizeFirst) {
    if (!readSize(pos)) return null;
    if (!readType(pos + sizeLen)) return null;
  } else {
    if (!readType(pos)) return null;
    if (!readSize(pos + typeLen)) return null;
  }

  // 扩展长度：size == 1 时，跟在块头字段之后（与字段顺序无关）。
  var headerSize = sizeLen + typeLen;
  if (rule.extendedSizeWhenOne && declaredSize == 1) {
    final extOffset = pos + sizeLen + typeLen;
    if (extOffset + 8 > limit) {
      ctx.report('文件在偏移 $extOffset 处截断，扩展长度字段不完整');
      return null;
    }
    declaredSize = _readUintBytes(ctx.source.read(extOffset, 8), rule.endian);
    headerSize += 8;
  }

  // --- 载荷长度 ---
  final payloadStart = pos + headerSize;
  final size = declaredSize;
  final int payloadSize;
  if (sizeUnknown || size == null) {
    payloadSize = limit - payloadStart;
  } else if (rule.sizeZeroMeansToEof && size == 0) {
    payloadSize = limit - payloadStart;
  } else if (rule.sizeIncludesHeader) {
    if (size < headerSize) {
      ctx.report('块 $type 在偏移 $pos 处声明的长度 $size 小于块头长度 $headerSize');
      final clipped = limit > payloadStart ? limit - payloadStart : 0;
      return _ChunkOutcome(
        node: ContainerNode(
          type: type,
          offset: pos,
          size: headerSize + clipped,
          dataOffset: payloadStart,
          dataSize: clipped,
          isOpaque: true,
        ),
        next: limit,
        stop: true,
      );
    }
    payloadSize = size - headerSize;
  } else {
    payloadSize = size;
  }

  // --- 截断检测：声明的长度超出可用范围 ---
  final dataEnd = payloadStart + payloadSize;
  if (dataEnd > limit) {
    final missing = dataEnd - limit;
    if (regionEnd < ctx.source.length) {
      // 父块声明的边界先到：子块的长度字段撒谎。
      ctx.report('块 $type 在偏移 $payloadStart 处声明的长度超出父块边界，还差 $missing 字节');
    } else {
      ctx.report('文件在偏移 $limit 处截断，声明长度还差 $missing 字节');
    }
    final clipped = limit > payloadStart ? limit - payloadStart : 0;
    return _ChunkOutcome(
      node: ContainerNode(
        type: type,
        offset: pos,
        size: headerSize + clipped,
        dataOffset: payloadStart,
        dataSize: clipped,
        isOpaque: true,
      ),
      next: limit,
      stop: true,
    );
  }

  // --- 对齐填充 ---
  var next = payloadStart + payloadSize;
  final padTo = rule.padTo;
  if (padTo != null && padTo > 1) {
    final rest = payloadSize % padTo;
    if (rest != 0) next += padTo - rest;
  }
  if (next > limit) {
    ctx.report('文件在偏移 $next 处截断，缺少对齐填充字节');
    final clipped = limit > payloadStart ? limit - payloadStart : 0;
    return _ChunkOutcome(
      node: ContainerNode(
        type: type,
        offset: pos,
        size: headerSize + clipped,
        dataOffset: payloadStart,
        dataSize: clipped,
        isOpaque: true,
      ),
      next: limit,
      stop: true,
    );
  }

  // --- 查表 ---
  final childSpec = _lookupChildSpec(scopes, type);
  var effective = childSpec;
  var opaque = childSpec == null || childSpec.opaque;
  var fields = const <SemanticField>[];
  final values = <String, Object?>{};

  if (childSpec != null && !childSpec.opaque) {
    final cursor = _Cursor(
      ctx.source,
      payloadStart,
      payloadStart + payloadSize,
    );
    final reader = _FieldReader(cursor, values, type);
    try {
      fields = reader.readFields(childSpec.fields);
      final dispatchOn = childSpec.dispatchOn;
      if (dispatchOn != null) {
        final key = _dispatchKey(values, scopes, dispatchOn);
        final alt = key == null ? null : _lookupChildSpec(scopes, key);
        if (alt != null && !identical(alt, childSpec)) {
          effective = alt;
          fields = <SemanticField>[...fields, ...reader.readFields(alt.fields)];
        } else {
          opaque = true;
        }
      }
    } on _FieldOverrun catch (e) {
      ctx.report('块 $type 在偏移 ${e.offset} 处的字段 ${e.fieldName} 超出块范围');
      return _ChunkOutcome(
        node: ContainerNode(
          type: type,
          offset: pos,
          size: headerSize + payloadSize,
          dataOffset: payloadStart,
          dataSize: payloadSize,
          isOpaque: true,
          fields: reader.parsed,
        ),
        next: next,
        stop: true,
      );
    }
  }

  // --- 递归子块 ---
  var children = const <ContainerNode>[];
  final childContainer = effective?.container;
  if (!opaque && childContainer != null) {
    if (level >= ctx.maxDepth) {
      opaque = true; // 递归深度超限：不再展开，标记不透明
    } else if (level + 1 <= levels) {
      final merged = <String, Object?>{...scopes.first.values, ...values};
      final childScopes = <_Scope>[
        _Scope(childContainer.children, merged),
        ...scopes,
      ];
      // 容器的载荷可能先跟一段固定前缀（RIFF 的 form type、FLAC 的 fLaC 魔数），
      // 跳过它再读子块，否则前缀会被当成子块头读出假尺寸。
      final prefix = childContainer.header.prefixBytes;
      final childStart = payloadStart + (prefix > payloadSize ? payloadSize : prefix);
      children = _parseChildren(
        ctx: ctx,
        container: childContainer,
        start: childStart,
        end: payloadStart + payloadSize,
        level: level + 1,
        levels: levels,
        scopes: childScopes,
      );
    }
  }

  final node = ContainerNode(
    type: type,
    offset: pos,
    size: headerSize + payloadSize,
    dataOffset: payloadStart,
    dataSize: payloadSize,
    isOpaque: opaque,
    children: children,
    fields: fields,
  );
  return _ChunkOutcome(node: node, next: next);
}

/// 在作用域链里按 type 查子块规格（近的优先）。
ChildSpec? _lookupChildSpec(List<_Scope> scopes, String type) {
  for (final scope in scopes) {
    final spec = scope.children[type];
    if (spec != null) return spec;
  }
  return null;
}

/// 取分派键：本块字段优先，找不到再沿作用域链向上找。
String? _dispatchKey(
  Map<String, Object?> values,
  List<_Scope> scopes,
  String fieldName,
) {
  final local = values[fieldName];
  if (local != null) return local.toString();
  for (final scope in scopes) {
    final inherited = scope.values[fieldName];
    if (inherited != null) return inherited.toString();
  }
  return null;
}

/// 带缓冲的字节游标，支持字节对齐读与位读。
class _Cursor {
  _Cursor(this.source, int start, int end)
    : _pos = start,
      _bitPos = start * 8,
      _end = end;

  final ByteSource source;
  final int _end;
  int _pos;
  int _bitPos;
  Uint8List _buf = Uint8List(0);
  int _bufStart = 0;

  /// 剩余字节数（字节对齐位置起算）。
  int get remainingBytes => _end - _pos;

  /// 当前读指针的**绝对**偏移（文件里的字节位置）。
  int get position => _pos;

  void _align() {
    if (_bitPos % 8 != 0) {
      _bitPos = (_bitPos + 7) & ~7;
      _pos = _bitPos ~/ 8;
    }
  }

  int _byteAt(int index) {
    if (index < _bufStart || index >= _bufStart + _buf.length) {
      final available = _end - index;
      final size = available < 4096 ? available : 4096;
      if (size <= 0) throw _FieldOverrun(index, '');
      _buf = source.read(index, size);
      _bufStart = index;
    }
    return _buf[index - _bufStart];
  }

  Uint8List readBytes(int count) {
    if (count < 0) throw _FieldOverrun(_pos, '');
    _align();
    if (_pos + count > _end) throw _FieldOverrun(_pos, '');
    final out = Uint8List(count);
    for (var i = 0; i < count; i++) {
      out[i] = _byteAt(_pos + i);
    }
    _pos += count;
    _bitPos += count * 8;
    return out;
  }

  /// 读 [count] 个位（MSB 优先），可跨字节。
  int readBits(int count) {
    if (count <= 0) return 0;
    var value = 0;
    for (var i = 0; i < count; i++) {
      final index = _bitPos ~/ 8;
      if (index >= _end) throw _FieldOverrun(index, '');
      final byte = _byteAt(index);
      final bit = (byte >> (7 - (_bitPos % 8))) & 1;
      value = (value << 1) | bit;
      _bitPos++;
    }
    _pos = _bitPos ~/ 8;
    return value;
  }
}

/// 读字段并产出语义字段。
class _FieldReader {
  _FieldReader(this.cursor, this.values, this.chunkType);

  final _Cursor cursor;
  final Map<String, Object?> values;
  final String chunkType;

  /// 已经读出来的字段（读失败时保留已读部分）。
  final List<SemanticField> parsed = [];

  List<SemanticField> readFields(List<FieldSpec> specs) {
    final out = <SemanticField>[];
    for (final spec in specs) {
      final field = readField(spec);
      out.add(field);
      parsed.add(field);
    }
    return out;
  }

  SemanticField readField(FieldSpec spec) {
    late final Object? value;
    // 读之前记下位置：字段是顺序从字节流里读的，读完之后的偏移差
    // 就是这个字段占的字节数——于是每个字段都能标出"它来自哪几个字节"。
    final start = cursor.position;
    try {
      value = _readValue(spec);
    } on _FieldOverrun catch (e) {
      throw _FieldOverrun(e.offset, spec.name);
    }
    final end = cursor.position;
    values[spec.name] = value;
    return SemanticField(
      key: spec.name,
      label: spec.name,
      value: value,
      origin: FieldOrigin.read,
      scope: FieldScope.file,
      source: chunkType,
      byteRange: end > start ? ByteRange(start, end) : null,
    );
  }

  Object? _readValue(FieldSpec spec) {
    final isArray = spec.count != null || spec.countFrom != null;
    if (!isArray) return _readSingle(spec);
    final count = _resolveCount(spec);
    final list = <Object?>[];
    for (var i = 0; i < count; i++) {
      list.add(_readSingle(spec));
    }
    return list;
  }

  Object? _readSingle(FieldSpec spec) {
    switch (spec.type) {
      case FieldType.uint8:
        return _readUint(1, spec.endian);
      case FieldType.uint16:
        return _readUint(2, spec.endian);
      case FieldType.uint24:
        return _readUint(3, spec.endian);
      case FieldType.uint32:
        return _readUint(4, spec.endian);
      case FieldType.uint64:
        return _readUint(8, spec.endian);
      case FieldType.sint8:
        return _toSigned(_readUint(1, spec.endian), 8);
      case FieldType.sint16:
        return _toSigned(_readUint(2, spec.endian), 16);
      case FieldType.sint32:
        return _toSigned(_readUint(4, spec.endian), 32);
      case FieldType.sint64:
        return _toSigned(_readUint(8, spec.endian), 64);
      case FieldType.bits:
        return cursor.readBits(spec.bitWidth ?? 0);
      case FieldType.fourcc:
        return String.fromCharCodes(cursor.readBytes(4));
      case FieldType.boolean:
        return cursor.readBits(1) != 0;
      case FieldType.bytes:
        return cursor.readBytes(_resolveLength(spec));
      case FieldType.utf8:
        return utf8.decode(
          cursor.readBytes(_resolveLength(spec)),
          allowMalformed: true,
        );
    }
  }

  int _readUint(int byteCount, Endian endian) {
    final bytes = cursor.readBytes(byteCount);
    var value = 0;
    if (endian == Endian.big) {
      for (var i = 0; i < byteCount; i++) {
        value = (value << 8) | bytes[i];
      }
    } else {
      for (var i = byteCount - 1; i >= 0; i--) {
        value = (value << 8) | bytes[i];
      }
    }
    return value;
  }

  int _resolveCount(FieldSpec spec) {
    if (spec.count != null) return spec.count!;
    final from = spec.countFrom;
    if (from == null) return 1;
    final value = values[from];
    if (value is int) return value;
    final fallback = spec.defaultValue;
    if (fallback is int) return fallback;
    return 0;
  }

  int _resolveLength(FieldSpec spec) {
    if (spec.length != null) return spec.length!;
    final from = spec.lengthFrom;
    if (from != null) {
      final value = values[from];
      if (value is int) return value;
      final fallback = spec.defaultValue;
      if (fallback is int) return fallback;
      return 0;
    }
    return cursor.remainingBytes;
  }
}

int _toSigned(int value, int bits) {
  if (bits >= 64) return value;
  final sign = 1 << (bits - 1);
  return value >= sign ? value - (1 << bits) : value;
}

/// 变长整数的宽度（字节数）；0 表示非法。
int _vintWidthAt(ByteSource source, int offset, int limit) {
  if (offset < 0 || offset >= limit) return 0;
  final first = source.read(offset, 1)[0];
  if (first == 0) return 0;
  var width = 1;
  var mask = 0x80;
  while ((first & mask) == 0) {
    mask >>= 1;
    width++;
  }
  return width;
}

/// 解码变长整数，返回 (值, 宽度)。
({int value, int width}) _decodeVint(Uint8List bytes) {
  final first = bytes[0];
  var width = 1;
  var mask = 0x80;
  while ((first & mask) == 0) {
    mask >>= 1;
    width++;
  }
  var value = first & (0xFF >> width);
  for (var i = 1; i < width; i++) {
    value = (value << 8) | bytes[i];
  }
  return (value: value, width: width);
}

/// 宽度为 [width] 的变长整数的最大值（= 未知长度哨兵）。
int _vintMaxValue(int width) => (1 << (7 * width)) - 1;

bool _isAllOnes(Uint8List bytes) {
  for (final byte in bytes) {
    if (byte != 0xFF) return false;
  }
  return bytes.isNotEmpty;
}

int _readUintBytes(Uint8List bytes, Endian endian) {
  var value = 0;
  if (endian == Endian.big) {
    for (final byte in bytes) {
      value = (value << 8) | byte;
    }
  } else {
    for (var i = bytes.length - 1; i >= 0; i--) {
      value = (value << 8) | bytes[i];
    }
  }
  return value;
}

String _toHex(Uint8List bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
  }
  return buffer.toString();
}
