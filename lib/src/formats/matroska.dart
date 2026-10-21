/// Matroska / WebM（EBML）的规格表与语义字段提取。
///
/// 规格表来自官方 EBML Schema（`ebml_matroska.xml`，转换后的结果在
/// `matroska_schema.dart`），由通用容器引擎（`core/engine.dart`）按表解析，
/// 这里只做两件事：
///
/// 1. 把 schema 表装配成引擎要的 [ContainerSpec] 树；
/// 2. 从结构树里提取语义字段（统一词表见 `.scratch/.../08-field-vocabulary.md`）。
///
/// 结构树上的元素节点 type 是元素 ID 的十六进制文本（如 `0x18538067`），
/// 因为 EBML 元素 ID 没有 ASCII 形式；用 [matroskaElementName] 可以换回元素名。
library;

import 'dart:convert';
import 'dart:typed_data';

import '../core/byte_source.dart';
import '../core/node.dart';
import '../core/position_index.dart';
import '../core/registry.dart';
import '../core/spec.dart';
import 'matroska_schema.dart';

/// EBML 头元素（`0x1A45DFA3`）。
const String kEbmlHeaderId = '0x1A45DFA3';

/// Segment 元素（`0x18538067`）——Matroska 的根元素。
const String kSegmentId = '0x18538067';

/// Info 元素（`0x1549A966`）——文件级元数据。
const String kInfoId = '0x1549A966';

/// Tracks 元素（`0x1654AE6B`）——轨道列表。
const String kTracksId = '0x1654AE6B';

/// TrackEntry 元素（`0xAE`）——单条轨道。
const String kTrackEntryId = '0xAE';

/// Video 元素（`0xE0`）。
const String kVideoId = '0xE0';

/// Audio 元素（`0xE1`）。
const String kAudioId = '0xE1';

/// Cluster 元素（承载媒体载荷）。
const String kClusterId = '0x1F43B675';

/// DefaultDuration（TrackEntry 的子元素，每帧的纳秒数）。
const String kDefaultDurationId = '0x23E383';

/// EBML 的通用块头：元素 ID 是变长整数，元素尺寸是变长整数。
///
/// - [HeaderRule.sizeIncludesHeader] 为 false：EBML 的尺寸只算载荷，不含块头；
/// - [HeaderRule.unknownSizeAllowed] 为 true：尺寸可以是"未知长度"哨兵
///   （RFC 8794 §6.2），此时收尾靠**路径**判定，不靠声明长度。
const HeaderRule _ebmlHeaderRule = HeaderRule(
  vintId: true,
  vintSize: true,
  unknownSizeAllowed: true,
  sizeIncludesHeader: false,
);

/// 载荷不可表驱动、只能当不透明叶子的元素。
///
/// - `0xA3` SimpleBlock / `0xA1` Block：4 种 lacing（No / Xiph / EBML / Fixed-size），
///   载荷布局在运行期才确定，规格表描述不了（RFC 9559 §10.3）；
/// - `0x465C` FileData：附件原文件可能很大，没必要整体读进内存。
const Set<String> _opaqueElementIds = <String>{'0xA3', '0xA1', '0x465C'};

final Map<String, EbmlElement> _elementsById = <String, EbmlElement>{
  for (final element in matroskaSchemaElements) element.id: element,
};

/// 按元素 ID 查 schema 条目（如 `0x18538067` → Segment）。
EbmlElement? matroskaElement(String id) => _elementsById[id];

/// 按元素 ID 查元素名；未知 ID 返回 null。
String? matroskaElementName(String id) => _elementsById[id]?.name;

/// 按 schema 声明的类型解码一个叶子元素的载荷（结构树视图用）。
///
/// 返回 int / double / String / DateTime；master 与 binary 元素返回 null。
Object? decodeMatroskaValue(ContainerNode node) => _decode(node);

ContainerSpec? _cachedSpec;
FormatSpec? _cachedFormat;

/// Matroska / WebM 的容器规格表（按 schema 装配出来的引擎表）。
///
/// 根节点的子块就是顶层元素（EBML 头 + Segment）。
ContainerSpec get matroskaContainerSpec => _cachedSpec ??= _buildSpec();

/// Matroska / WebM 的注册项。WebM 是 Matroska 的子集，共用这一张表，
/// 靠 EBML 头里的 `DocType` 区分。
FormatSpec get matroskaFormat => _cachedFormat ??= FormatSpec(
  name: 'Matroska',
  container: matroskaContainerSpec,
  extractor: extractMatroskaFields,
  detect: _detectMatroska,
  positionIndexBuilder: buildMatroskaPositionIndex,
);

/// Matroska 的位置索引：按 **Cluster** 区间与总时长线性估算。
///
/// Cluster 在树里的 type 是十六进制元素 ID（`0x1F43B675`），不是 ASCII 名字——
/// 这类格式知识只能留在格式模块里。
PositionIndex? buildMatroskaPositionIndex(
  ContainerNode root,
  Duration duration,
) {
  final clusters = findNodes(root, kClusterId);
  if (clusters.isEmpty) return null;

  var start = clusters.first.offset;
  var end = start;
  for (final cluster in clusters) {
    if (cluster.offset < start) start = cluster.offset;
    if (cluster.offset + cluster.size > end)
      end = cluster.offset + cluster.size;
  }
  if (end <= start) return null;
  return PositionIndex(duration: duration, payload: ByteRange(start, end));
}

/// 把 Matroska / WebM 注册进全局格式表。
void registerMatroska() => registerFormat(matroskaFormat);

/// 从文件头判断是不是 EBML（Matroska / WebM）。
///
/// EBML 文件以 EBML 头元素 `0x1A45DFA3` 开头。
bool _detectMatroska(ByteSource source) {
  if (source.length < 4) return false;
  final magic = source.read(0, 4);
  return magic[0] == 0x1A &&
      magic[1] == 0x45 &&
      magic[2] == 0xDF &&
      magic[3] == 0xA3;
}

// ---------------------------------------------------------------------------
// 规格表装配
// ---------------------------------------------------------------------------

ContainerSpec _buildSpec() {
  // 1. 按 schema 的 path 还原父子关系（path 里的 '+' 表示递归元素）。
  final childrenByParent = <String, List<EbmlElement>>{};
  final globals = <EbmlElement>[];
  for (final element in matroskaSchemaElements) {
    if (element.global) {
      globals.add(element);
      continue;
    }
    final path = element.path.replaceAll('+', '');
    final index = path.lastIndexOf(r'\');
    final parent = index <= 0 ? '' : path.substring(0, index);
    (childrenByParent[parent] ??= <EbmlElement>[]).add(element);
    if (element.recursive) {
      // 递归元素（ChapterAtom / SimpleTag）也可以包含自己。
      (childrenByParent[path] ??= <EbmlElement>[]).add(element);
    }
  }

  // 2. 每个 master 元素一张子表（先建空壳，好让递归元素能引用自己）。
  final specs = <String, ContainerSpec>{};
  for (final element in matroskaSchemaElements) {
    if (!element.isMaster) continue;
    specs[element.id] = ContainerSpec(
      name: element.name,
      header: _ebmlHeaderRule,
      children: <String, ChildSpec>{},
    );
  }

  // 3. 填子表：master 元素挂自己的子表，全局元素（Void / CRC-32）挂进所有 master。
  for (final element in matroskaSchemaElements) {
    if (!element.isMaster) continue;
    final table = specs[element.id]!.children;
    for (final child
        in childrenByParent[element.path] ?? const <EbmlElement>[]) {
      table[child.id] = _childSpec(child, specs);
    }
    for (final global in globals) {
      table[global.id] = _childSpec(global, specs);
    }
  }

  // 4. 根表：顶层元素（EBML 头 + Segment）。
  final rootChildren = <String, ChildSpec>{};
  final root = ContainerSpec(
    name: 'Matroska',
    rootType: 'Matroska',
    header: _ebmlHeaderRule,
    children: rootChildren,
  );
  for (final child in childrenByParent[''] ?? const <EbmlElement>[]) {
    rootChildren[child.id] = _childSpec(child, specs);
  }
  return root;
}

ChildSpec _childSpec(EbmlElement element, Map<String, ContainerSpec> specs) {
  if (element.isMaster) {
    return ChildSpec(type: element.id, container: specs[element.id]);
  }
  if (_opaqueElementIds.contains(element.id)) {
    return ChildSpec(type: element.id, opaque: true);
  }
  // 叶子元素：载荷按 schema 的类型整块读出来，由提取器按类型解码。
  return ChildSpec(
    type: element.id,
    fields: <FieldSpec>[FieldSpec(element.name, type: FieldType.bytes)],
  );
}

// ---------------------------------------------------------------------------
// 语义字段
// ---------------------------------------------------------------------------

/// 一条轨道的语义字段。
class MatroskaTrack {
  const MatroskaTrack({
    required this.index,
    required this.node,
    required this.fields,
  });

  /// 轨道序号（0 起，与 [SemanticField.trackIndex] 一致）。
  final int index;

  /// 对应的 TrackEntry 节点（轨道级字段挂在它上面）。
  final ContainerNode node;

  /// 该轨道的语义字段。
  final List<SemanticField> fields;
}

/// 按作用域分组后的 Matroska 语义字段。
class MatroskaSemantics {
  const MatroskaSemantics({required this.fileFields, required this.tracks});

  /// 文件级字段（挂在根节点上）。
  final List<SemanticField> fileFields;

  /// 轨道级字段（各自挂在对应的 TrackEntry 节点上）。
  final List<MatroskaTrack> tracks;

  /// 全部字段：文件级在前，轨道级按轨道序号在后。
  List<SemanticField> get allFields => <SemanticField>[
    ...fileFields,
    for (final track in tracks) ...track.fields,
  ];
}

/// 叶子提取器：从结构树里取 Matroska / WebM 的语义字段（不重复解析字节）。
List<SemanticField> extractMatroskaFields(ContainerNode root) =>
    extractMatroskaSemantics(root).allFields;

/// 提取 Matroska / WebM 的语义字段，并按文件级 / 轨道级分组。
///
/// 轨道级字段挂在对应的 TrackEntry 节点上（见 [MatroskaTrack.node]），
/// 文件级字段挂在根节点上。
MatroskaSemantics extractMatroskaSemantics(ContainerNode root) {
  final fileFields = <SemanticField>[];
  final tracks = <MatroskaTrack>[];

  final header = _childOf(root, kEbmlHeaderId);
  final segment = _childOf(root, kSegmentId);

  // 容器格式：EBML 头里的 DocType（matroska / webm）。
  final docType = _stringOf(header, '0x4282');
  if (docType != null) {
    fileFields.add(
      SemanticField(
        key: 'container_format',
        label: '容器格式',
        value: _containerFormatName(docType),
        source: 'EBML/DocType',
      ),
    );
  }

  // 文件大小。
  fileFields.add(
    SemanticField(
      key: 'file_size',
      label: '文件大小',
      value: root.size,
      unit: 'byte',
      source: 'file',
    ),
  );

  // 时长：Info/Duration 的单位是 TimestampScale，换算成秒。
  final info = _childOf(segment, kInfoId);
  final timestampScale = _intOf(info, '0x2AD7B1');
  if (timestampScale != null) {
    fileFields.add(
      SemanticField(
        key: 'timestamp_scale',
        label: '时间戳刻度',
        value: timestampScale,
        unit: 'ns',
        source: 'Info/TimestampScale',
      ),
    );
  }
  final durationTicks = _floatOf(info, '0x4489');
  if (durationTicks != null) {
    final scale = timestampScale ?? 1000000;
    final seconds = durationTicks * scale / 1000000000;
    fileFields.add(
      SemanticField(
        key: 'duration',
        label: '时长',
        value: seconds,
        unit: 's',
        source: 'Info/Duration',
      ),
    );
    if (seconds > 0) {
      fileFields.add(
        SemanticField(
          key: 'overall_bitrate',
          label: '平均码率',
          value: (root.size * 8 / seconds).round(),
          unit: 'bit/s',
          origin: FieldOrigin.derived,
          source: 'derived',
        ),
      );
    }
  }

  // 轨道级字段。
  final tracksNode = _childOf(segment, kTracksId);
  final entries = _childrenOf(tracksNode, kTrackEntryId);
  for (var index = 0; index < entries.length; index++) {
    final entry = entries[index];
    final fields = <SemanticField>[];

    void add(
      String key,
      String label,
      Object? value, {
      String? unit,
      String? source,
    }) {
      if (value == null) return;
      fields.add(
        SemanticField(
          key: key,
          label: label,
          value: value,
          unit: unit,
          scope: FieldScope.track,
          trackIndex: index,
          source: source,
        ),
      );
    }

    add('track_index', '轨道序号', index, source: 'TrackEntry');

    final trackType = _intOf(entry, '0x83');
    if (trackType != null) {
      add(
        'track_type',
        '轨道类型',
        _trackTypeName(trackType),
        source: 'TrackEntry/TrackType',
      );
    }

    final codec = _stringOf(entry, '0x86');
    if (codec != null) {
      add('codec', '编码标识', codec, source: 'TrackEntry/CodecID');
    }

    final language = _stringOf(entry, '0x22B59C');
    if (language != null) {
      add('language', '语言', language, source: 'TrackEntry/Language');
    }

    final video = _childOf(entry, kVideoId);
    add(
      'width',
      '宽度',
      _intOf(video, '0xB0'),
      unit: 'px',
      source: 'Video/PixelWidth',
    );
    add(
      'height',
      '高度',
      _intOf(video, '0xBA'),
      unit: 'px',
      source: 'Video/PixelHeight',
    );
    final frameRate = _floatOf(video, '0x2383E3');
    if (frameRate != null) {
      add(
        'frame_rate',
        '帧率',
        frameRate,
        unit: 'fps',
        source: 'Video/FrameRate',
      );
    } else {
      // Matroska 的 FrameRate（0x2383E3）几乎没人写；常见的是
      // DefaultDuration（每帧多少纳秒），帧率 = 1e9 / DefaultDuration。
      final defaultDuration = _intOf(entry, kDefaultDurationId);
      if (defaultDuration != null && defaultDuration > 0) {
        add(
          'frame_rate',
          '帧率',
          1000000000 / defaultDuration,
          unit: 'fps',
          source: 'TrackEntry/DefaultDuration',
        );
      }
    }

    final audio = _childOf(entry, kAudioId);
    final samplingFrequency = _floatOf(audio, '0xB5');
    if (samplingFrequency != null) {
      add(
        'sample_rate',
        '采样率',
        samplingFrequency.round(),
        unit: 'Hz',
        source: 'Audio/SamplingFrequency',
      );
    }
    add('channels', '声道数', _intOf(audio, '0x9F'), source: 'Audio/Channels');
    add(
      'bit_depth',
      '位深',
      _intOf(audio, '0x6264'),
      unit: 'bit',
      source: 'Audio/BitDepth',
    );

    tracks.add(MatroskaTrack(index: index, node: entry, fields: fields));
  }

  return MatroskaSemantics(fileFields: fileFields, tracks: tracks);
}

String _containerFormatName(String docType) => switch (docType.toLowerCase()) {
  // 原样保留 DocType 的字面值（'matroska' / 'webm'）——这是文件里写的东西，
  // 导出 JSON 时应该保真，不要在这里改大小写。
  'webm' => 'webm',
  'matroska' => 'matroska',
  _ => docType,
};

/// TrackType 的取值（RFC 9559 §5.1.2）。
String _trackTypeName(int value) => switch (value) {
  1 => 'video',
  2 => 'audio',
  3 => 'complex',
  0x10 => 'logo',
  0x11 => 'subtitle',
  0x12 => 'buttons',
  0x20 => 'control',
  _ => 'unknown',
};

// ---------------------------------------------------------------------------
// 结构树查找与值解码
// ---------------------------------------------------------------------------

ContainerNode? _childOf(ContainerNode? node, String id) {
  if (node == null) return null;
  for (final child in node.children) {
    if (child.type == id) return child;
  }
  return null;
}

List<ContainerNode> _childrenOf(ContainerNode? node, String id) {
  if (node == null) return const <ContainerNode>[];
  return node.children.where((child) => child.type == id).toList();
}

int? _intOf(ContainerNode? node, String id) {
  final value = _valueOf(node, id);
  return value is int ? value : null;
}

double? _floatOf(ContainerNode? node, String id) {
  final value = _valueOf(node, id);
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return null;
}

String? _stringOf(ContainerNode? node, String id) {
  final value = _valueOf(node, id);
  return value is String ? value : null;
}

/// 取子元素的解码值。
Object? _valueOf(ContainerNode? node, String id) {
  final child = _childOf(node, id);
  if (child == null) return null;
  return _decode(child);
}

/// 按 schema 声明的类型解码叶子元素的载荷。
Object? _decode(ContainerNode node) {
  if (node.fields.isEmpty) return null;
  final raw = node.fields.first.value;
  if (raw is! Uint8List) return null;
  switch (matroskaElement(node.type)?.type) {
    case EbmlElementType.uinteger:
      return _readUint(raw);
    case EbmlElementType.integer:
      return _readInt(raw);
    case EbmlElementType.float:
      return _readFloat(raw);
    case EbmlElementType.string:
      return _readString(raw);
    case EbmlElementType.utf8:
      return _readUtf8(raw);
    case EbmlElementType.date:
      return _readDate(raw);
    case EbmlElementType.master:
    case EbmlElementType.binary:
    case null:
      return null;
  }
}

/// 无符号整数：大端最短编码（1–8 字节）。
int? _readUint(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > 8) return null;
  var value = 0;
  for (final byte in bytes) {
    value = (value << 8) | byte;
  }
  return value;
}

/// 有符号整数：大端二补码最短编码。
int? _readInt(Uint8List bytes) {
  final value = _readUint(bytes);
  if (value == null || bytes.length >= 8) return value;
  final sign = 1 << (8 * bytes.length - 1);
  return value >= sign ? value - (1 << (8 * bytes.length)) : value;
}

/// 浮点数：4 字节 float32 或 8 字节 float64，均为大端。
double? _readFloat(Uint8List bytes) {
  if (bytes.length != 4 && bytes.length != 8) return null;
  final view = ByteData.sublistView(bytes);
  return bytes.length == 4
      ? view.getFloat32(0, Endian.big)
      : view.getFloat64(0, Endian.big);
}

/// ASCII 字符串（尾部 NUL 补齐要去掉）。
String? _readString(Uint8List bytes) {
  if (bytes.isEmpty) return null;
  var end = bytes.length;
  while (end > 0 && bytes[end - 1] == 0) {
    end--;
  }
  return String.fromCharCodes(bytes.sublist(0, end));
}

/// UTF-8 字符串。
String? _readUtf8(Uint8List bytes) {
  if (bytes.isEmpty) return null;
  var end = bytes.length;
  while (end > 0 && bytes[end - 1] == 0) {
    end--;
  }
  return utf8.decode(bytes.sublist(0, end), allowMalformed: true);
}

/// 日期：自 2001-01-01T00:00:00 UTC 起的纳秒数。
DateTime? _readDate(Uint8List bytes) {
  final value = _readInt(bytes);
  if (value == null || bytes.length != 8) return null;
  return DateTime.utc(2001).add(Duration(microseconds: value ~/ 1000));
}
