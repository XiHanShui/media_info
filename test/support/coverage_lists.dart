/// **块覆盖率清单**：每个格式一份「必须能在结构树里找到的块类型集合」。
///
/// 为什么要有它：golden 快照防的是**回归**，防不住「解析器从一开始就漏了某个块」
/// ——golden 也是我们自己产的，漏了就是两边一起漏。这份清单是人写的、
/// 直接来自规范，不继承解析器的盲区（见 `.scratch/media-info-mvp/spec.md`
/// 的 Testing Decisions 段）。
///
/// 每一条都注明**依据**（哪份规范的哪一节），方便后人核对。
///
/// 用法：
///
/// ```dart
/// final result = parseFixtureFile('mp4_h264_aac_320x240.normal.mp4');
/// expect(missingRequiredBlocks(result.root, coverageFor('MP4')), isEmpty);
/// ```
library;

import 'package:media_info/src/core/node.dart';
import 'package:media_info/src/formats/matroska.dart';

/// 块覆盖率清单里的一条。
class BlockCoverageEntry {
  /// 记录一条块类型要求。
  ///
  /// [type] 是结构树里应该出现的块类型：绝大多数格式是文件里字面的块名
  /// （`ftyp`、`fmt `、`STREAMINFO`…）；Matroska 家族用**规范名**
  /// （`Segment`、`Info`…），因为节点 type 是元素 ID 的十六进制文本，
  /// 由 [canonicalBlockType] 换回规范名。
  ///
  /// [required] 为 false 表示这条是**可选**的：素材里可能压根没有这种块
  /// （ffmpeg 不写 `uuid` / `skip`），断言会跳过它。可选条目照样写清依据，
  /// 方便将来补素材时升级成必查。
  ///
  /// [spec] 是这条要求的出处（规范 + 条款 + 块名）。
  const BlockCoverageEntry(
    this.type, {
    this.required = true,
    required this.spec,
  });

  /// 结构树里应该出现的块类型。
  final String type;

  /// 是否必须出现在结构树里。
  final bool required;

  /// 依据：这条要求出自哪份规范的哪一节。
  final String spec;

  @override
  String toString() => '$type${required ? '' : '（可选）'}';
}

/// 一个格式的块覆盖率清单。
class BlockCoverage {
  /// 记录一份清单。
  const BlockCoverage({
    required this.format,
    required this.spec,
    required this.entries,
  });

  /// 格式名（与 `FormatSpec.name` 对齐：`WAV` / `MP4` / `Matroska`…）。
  final String format;

  /// 整份清单的总体依据。
  final String spec;

  /// 清单里的全部条目。
  final List<BlockCoverageEntry> entries;

  /// 必查的条目。
  List<BlockCoverageEntry> get requiredEntries =>
      entries.where((e) => e.required).toList(growable: false);

  /// 可选的条目。
  List<BlockCoverageEntry> get optionalEntries =>
      entries.where((e) => !e.required).toList(growable: false);

  /// 必查的块类型（断言用）。
  List<String> get requiredTypes => <String>[
    for (final entry in requiredEntries) entry.type,
  ];

  /// 可选的块类型（断言跳过，仅供人看）。
  List<String> get optionalTypes => <String>[
    for (final entry in optionalEntries) entry.type,
  ];
}

// ---------------------------------------------------------------------------
// 各格式的清单
// ---------------------------------------------------------------------------

/// ISO base media file format 的公共条目（MP4 与 MOV 共用）。
const List<BlockCoverageEntry> _isoBmffCommon = <BlockCoverageEntry>[
  BlockCoverageEntry(
    'ftyp',
    spec: 'ISO/IEC 14496-12 §4.3「File Type Box」：声明文件用的品牌',
  ),
  BlockCoverageEntry('moov', spec: 'ISO/IEC 14496-12 §4.2「Movie Box」：所有元数据的容器'),
  BlockCoverageEntry('trak', spec: 'ISO/IEC 14496-12 §4.3「Track Box」：一条轨道'),
  BlockCoverageEntry('mdia', spec: 'ISO/IEC 14496-12 §4.2「Media Box」：轨道里的媒体信息'),
  BlockCoverageEntry(
    'minf',
    spec: 'ISO/IEC 14496-12 §4.2「Media Information Box」',
  ),
  BlockCoverageEntry(
    'stbl',
    spec: 'ISO/IEC 14496-12 §4.2「Sample Table Box」：采样表',
  ),
  BlockCoverageEntry(
    'stsd',
    spec: 'ISO/IEC 14496-12 §4.3「Sample Description Box」：采样描述',
  ),
  BlockCoverageEntry(
    'mdat',
    spec: 'ISO/IEC 14496-12 §4.2「Media Data Box」：媒体数据',
  ),
];

/// `free` 盒（ISO/IEC 14496-12 §8.1.2「Free Space Box」）。
const BlockCoverageEntry _freeEntry = BlockCoverageEntry(
  'free',
  spec: 'ISO/IEC 14496-12 §8.1.2「Free Space Box」：占位用的自由空间',
);

/// `skip` 盒：`free` 盒的 QuickTime 变体名。
const BlockCoverageEntry _skipEntry = BlockCoverageEntry(
  'skip',
  required: false,
  spec:
      'ISO/IEC 14496-12 §8.1.2「Free Space Box」的 QuickTime 变体名（`skip`）；'
      'ffmpeg 素材不写它，故列为可选',
);

/// `uuid` 盒。
const BlockCoverageEntry _uuidEntry = BlockCoverageEntry(
  'uuid',
  required: false,
  spec:
      'ISO/IEC 14496-12 §8.10「User Extension Box」；'
      'ffmpeg 素材不写它，故列为可选',
);

/// `wide` 盒（QuickTime 专有）。
const BlockCoverageEntry _wideEntry = BlockCoverageEntry(
  'wide',
  spec:
      'Apple QuickTime File Format「Wide Box」：'
      'ISO/IEC 14496-12 未定义它，QuickTime 素材用它占位',
);

/// Matroska 家族的公共条目（MKV 与 WebM 共用，块名是规范名）。
const List<BlockCoverageEntry> _matroskaCommon = <BlockCoverageEntry>[
  BlockCoverageEntry('EBML', spec: 'RFC 8794 §5.1「EBML Header」：每个 EBML 文件的头'),
  BlockCoverageEntry('Segment', spec: 'RFC 9559 §5.1「Segment」：Matroska 的根元素'),
  BlockCoverageEntry('Info', spec: 'RFC 9559 §5.2「Info」：文件级元数据'),
  BlockCoverageEntry('Tracks', spec: 'RFC 9559 §5.3「Tracks」：轨道列表'),
  BlockCoverageEntry('TrackEntry', spec: 'RFC 9559 §5.3.1「TrackEntry」：一条轨道'),
  BlockCoverageEntry('Video', spec: 'RFC 9559 §5.3.1.6「Video」：视频轨道参数'),
  BlockCoverageEntry('Audio', spec: 'RFC 9559 §5.3.1.7「Audio」：音频轨道参数'),
];

/// 全部格式的块覆盖率清单，键是格式名。
const Map<String, BlockCoverage> blockCoverageLists = <String, BlockCoverage>{
  'WAV': BlockCoverage(
    format: 'WAV',
    spec:
        'RIFF 规范（Microsoft/IBM, 1991）与 Microsoft Multimedia Programming '
        'Interface 里的 WAVE 格式说明',
    entries: <BlockCoverageEntry>[
      BlockCoverageEntry(
        'RIFF',
        spec: 'RIFF 规范「RIFF 块」：WAVE 文件的根块，载荷开头是 form type `WAVE`',
      ),
      BlockCoverageEntry(
        'fmt ',
        spec:
            'Microsoft Multimedia Programming Interface「Format Chunk」'
            '（`fmt `）：格式参数',
      ),
      BlockCoverageEntry(
        'data',
        spec:
            'Microsoft Multimedia Programming Interface「Data Chunk」'
            '（`data`）：采样数据',
      ),
      BlockCoverageEntry(
        'LIST',
        required: false,
        spec:
            'RIFF 规范「List Chunk」：ffmpeg 素材用它写 `INFO` 厂商信息，'
            '解析器不能把它连同子块一起丢掉',
      ),
      BlockCoverageEntry(
        'fact',
        required: false,
        spec:
            'Microsoft Multimedia Programming Interface「Fact Chunk」'
            '（`fact`）：非 PCM 压缩格式需要',
      ),
      BlockCoverageEntry(
        'JUNK',
        required: false,
        spec: 'RIFF 规范「Junk Chunk」：对齐填充',
      ),
    ],
  ),
  'AIFF': BlockCoverage(
    format: 'AIFF',
    spec: 'Apple AIFF 规范（Apple Computer, 1991）与 AIFF-C 规范',
    entries: <BlockCoverageEntry>[
      BlockCoverageEntry(
        'FORM',
        spec: 'AIFF 规范「FORM chunk」：AIFF 文件的根块，form type 是 `AIFF`',
      ),
      BlockCoverageEntry(
        'COMM',
        spec: 'AIFF 规范「COMM chunk」：声道数 / 采样帧数 / 采样率 / 位深',
      ),
      BlockCoverageEntry('SSND', spec: 'AIFF 规范「SSND chunk」：声音数据'),
      BlockCoverageEntry(
        'ID3 ',
        required: false,
        spec: 'AIFF-C 规范「ID3 chunk」：可选的标签',
      ),
      BlockCoverageEntry(
        'ANNO',
        required: false,
        spec: 'AIFF 规范「Annotation chunk」：可选的注释',
      ),
    ],
  ),
  'FLAC': BlockCoverage(
    format: 'FLAC',
    spec: 'RFC 9639《FLAC》(2024-12)',
    entries: <BlockCoverageEntry>[
      BlockCoverageEntry(
        'STREAMINFO',
        spec: 'RFC 9639 §8.2「STREAMINFO」：必选的第一个元数据块',
      ),
      BlockCoverageEntry(
        'VORBIS_COMMENT',
        spec:
            'RFC 9639 §8.6「VORBIS_COMMENT」：规范里是可选块，'
            '但本项目的 ffmpeg 素材必带，必须能解析出来',
      ),
      BlockCoverageEntry(
        'PADDING',
        required: false,
        spec: 'RFC 9639 §8.7「PADDING」',
      ),
      BlockCoverageEntry(
        'SEEKTABLE',
        required: false,
        spec: 'RFC 9639 §8.3「SEEKTABLE」',
      ),
      BlockCoverageEntry(
        'CUESHEET',
        required: false,
        spec: 'RFC 9639 §8.5「CUESHEET」',
      ),
      BlockCoverageEntry(
        'PICTURE',
        required: false,
        spec: 'RFC 9639 §8.4「PICTURE」',
      ),
      BlockCoverageEntry(
        'APPLICATION',
        required: false,
        spec: 'RFC 9639 §8.8「APPLICATION」',
      ),
    ],
  ),
  'MP3': BlockCoverage(
    format: 'MP3',
    spec: 'ISO/IEC 11172-3 §2.4.2.3（MPEG-1 音频帧头）与 ID3v2.4 规范 §3',
    entries: <BlockCoverageEntry>[
      BlockCoverageEntry(
        'MPEG Audio Frame',
        spec:
            'ISO/IEC 11172-3 §2.4.2.3「MPEG Audio frame header」：'
            'MP3 没有块树，一帧一个节点',
      ),
      BlockCoverageEntry(
        'ID3v2',
        required: false,
        spec: 'ID3v2.4 规范 §3「ID3v2 header」：文件开头的标签',
      ),
    ],
  ),
  'MP4': BlockCoverage(
    format: 'MP4',
    spec: 'ISO/IEC 14496-12（ISO base media file format）',
    entries: <BlockCoverageEntry>[
      ..._isoBmffCommon,
      _freeEntry,
      _skipEntry,
      _uuidEntry,
    ],
  ),
  'MOV': BlockCoverage(
    format: 'MOV',
    spec:
        'ISO/IEC 14496-12（ISO base media file format）'
        '与 Apple QuickTime File Format',
    entries: <BlockCoverageEntry>[
      ..._isoBmffCommon,
      _wideEntry,
      BlockCoverageEntry(
        'free',
        required: false,
        spec:
            'ISO/IEC 14496-12 §8.1.2「Free Space Box」；'
            '本项目的 MOV 素材用 `wide` 占位，故列为可选',
      ),
      _skipEntry,
      _uuidEntry,
    ],
  ),
  'MKV': BlockCoverage(
    format: 'MKV',
    spec: 'RFC 9559（Matroska）与 RFC 8794（EBML）',
    entries: <BlockCoverageEntry>[..._matroskaCommon],
  ),
  'WebM': BlockCoverage(
    format: 'WebM',
    spec: 'RFC 9559（Matroska）的 WebM 子集与 RFC 8794（EBML）',
    entries: <BlockCoverageEntry>[..._matroskaCommon],
  ),
};

/// 取某个格式的清单；格式名不认识时抛 [ArgumentError]。
BlockCoverage coverageFor(String format) {
  final coverage = blockCoverageLists[format];
  if (coverage == null) {
    throw ArgumentError(
      '没有 $format 的块覆盖率清单；'
      '已知格式：${blockCoverageLists.keys.join(' / ')}',
    );
  }
  return coverage;
}

/// 用**规范名**做块类型的格式（Matroska 家族）。
///
/// EBML 元素 ID 没有 ASCII 形式，结构树里节点的 type 是元素 ID 的十六进制文本
/// （如 `0x18538067`），要拿规范名得用 [matroskaElementName] 换回来。
const Set<String> kElementNameFormats = <String>{'MKV', 'WebM'};

/// 把结构树里某个节点的块类型归一化成**规范名**。
///
/// Matroska 家族走 [matroskaElementName]（换不回来就原样返回）；
/// 其它格式的块名本来就是规范里的字面名，原样返回。
String canonicalBlockType(String format, String nodeType) {
  if (kElementNameFormats.contains(format)) {
    return matroskaElementName(nodeType) ?? nodeType;
  }
  return nodeType;
}

/// 结构树里出现过的所有块类型（规范名，去重）。
Set<String> collectBlockTypes(ContainerNode root, {required String format}) {
  final types = <String>{};
  void walk(ContainerNode node) {
    types.add(canonicalBlockType(format, node.type));
    for (final child in node.children) {
      walk(child);
    }
  }

  walk(root);
  return types;
}

/// 清单里**必查**但结构树里找不到的块类型。
///
/// 返回空列表表示清单全部满足；非空时每一项都是「应该能找到却没找到」的块。
List<String> missingRequiredBlocks(ContainerNode root, BlockCoverage coverage) {
  final found = collectBlockTypes(root, format: coverage.format);
  return <String>[
    for (final entry in coverage.requiredEntries)
      if (!found.contains(entry.type)) entry.type,
  ];
}
