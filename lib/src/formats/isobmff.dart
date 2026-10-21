/// ISO base media file format（MP4 / MOV）的规格表与叶子提取器。
///
/// 结构按 ISO/IEC 14496-12 的块层级建模：
/// `moov` → `trak` → `mdia` → `minf` → `stbl` → `stsd`。
///
/// 表表达不了的三处留了手写逃生口：
///
/// - `stsd` 的 sample entry 类型是**动态**的（`avc1`/`mp4a`/`mp4v`…）→ 用
///   `dispatchOn` 走二级表；
/// - `stz2` 的样本大小位宽由载荷决定（4/8/16，4 位时半字节打包）→ 手写读取器；
/// - `avcC`/`hvcC`/`esds`/`colr` 定义在 14496-15 等别的规范里 → 不透明叶子。
library;

import 'dart:typed_data';

import '../core/byte_source.dart';
import '../core/node.dart';
import '../core/registry.dart';
import '../core/spec.dart';

// ---------------------------------------------------------------------------
// 规格表
// ---------------------------------------------------------------------------

/// ISO BMFF 的块头规则：`size`(u32) + `type`(fourcc)。
///
/// - `size == 1` → 随后是 64 位 `largesize`；
/// - `size == 0` → 该块延伸到文件末尾；
/// - 长度字段排在类型字段**之前**（ISO 的 box 头与其它容器相反）。
const HeaderRule _isoHeader = HeaderRule(
  typeBytes: 4,
  sizeBytes: 4,
  sizeIncludesHeader: true,
  sizeZeroMeansToEof: true,
  extendedSizeWhenOne: true,
  sizeFirst: true,
);

/// `dref` 的载荷前面有 8 字节（version/flags + entry_count），跳过才是子块。
const HeaderRule _drefHeader = HeaderRule(
  typeBytes: 4,
  sizeBytes: 4,
  sizeIncludesHeader: true,
  sizeZeroMeansToEof: true,
  extendedSizeWhenOne: true,
  sizeFirst: true,
  prefixBytes: 8,
);

/// 视觉 sample entry（`avc1`/`hvc1`/`mp4v`…）的固定字段。
///
/// 字段从 sample entry 的载荷起点开始（块头之后）。
const List<FieldSpec> _visualSampleEntryFields = [
  FieldSpec('reserved', type: FieldType.bytes, length: 6),
  FieldSpec('data_reference_index', type: FieldType.uint16),
  FieldSpec('pre_defined', type: FieldType.uint16),
  FieldSpec('reserved_1', type: FieldType.uint16),
  FieldSpec('pre_defined_1', type: FieldType.bytes, length: 12),
  FieldSpec('width', type: FieldType.uint16),
  FieldSpec('height', type: FieldType.uint16),
  FieldSpec('horizresolution', type: FieldType.uint32),
  FieldSpec('vertresolution', type: FieldType.uint32),
  FieldSpec('reserved_2', type: FieldType.uint32),
  FieldSpec('frame_count', type: FieldType.uint16),
  FieldSpec('compressorname', type: FieldType.bytes, length: 32),
  FieldSpec('depth', type: FieldType.uint16),
  FieldSpec('pre_defined_2', type: FieldType.sint16),
];

/// 音频 sample entry（`mp4a`/`ac-3`/`Opus`…）的固定字段。
const List<FieldSpec> _audioSampleEntryFields = [
  FieldSpec('reserved', type: FieldType.bytes, length: 6),
  FieldSpec('data_reference_index', type: FieldType.uint16),
  FieldSpec('sample_entry_version', type: FieldType.uint16),
  FieldSpec('sample_entry_revision', type: FieldType.uint16),
  FieldSpec('sample_entry_vendor', type: FieldType.uint32),
  FieldSpec('channelcount', type: FieldType.uint16),
  FieldSpec('samplesize', type: FieldType.uint16),
  FieldSpec('compression_id', type: FieldType.uint16),
  FieldSpec('packet_size', type: FieldType.uint16),
  FieldSpec('samplerate', type: FieldType.uint32),
];

// --- 文件级块 ---------------------------------------------------------------

const ChildSpec _ftypSpec = ChildSpec(
  type: 'ftyp',
  fields: [
    FieldSpec('major_brand', type: FieldType.fourcc),
    FieldSpec('minor_version', type: FieldType.uint32),
    FieldSpec('compatible_brands', type: FieldType.bytes),
  ],
);

/// `mvhd`（FullBox，version 0 布局）。
///
/// version 1 的创建/修改时间与时长是 64 位，通用引擎不支持按 version 切换
/// 字段宽度——遇到 version 1 时提取器会跳过依赖 timescale/duration 的字段。
const ChildSpec _mvhdSpec = ChildSpec(
  type: 'mvhd',
  fields: [
    FieldSpec('version', type: FieldType.uint8),
    FieldSpec('flags', type: FieldType.uint24),
    FieldSpec('creation_time', type: FieldType.uint32),
    FieldSpec('modification_time', type: FieldType.uint32),
    FieldSpec('timescale', type: FieldType.uint32),
    FieldSpec('duration', type: FieldType.uint32),
    FieldSpec('rate', type: FieldType.uint32),
    FieldSpec('volume', type: FieldType.uint16),
    FieldSpec('reserved', type: FieldType.bytes, length: 10),
    FieldSpec('matrix', type: FieldType.bytes, length: 36),
    FieldSpec('pre_defined', type: FieldType.bytes, length: 24),
    FieldSpec('next_track_id', type: FieldType.uint32),
  ],
);

/// `tkhd`（FullBox，version 0 布局）。
const ChildSpec _tkhdSpec = ChildSpec(
  type: 'tkhd',
  fields: [
    FieldSpec('version', type: FieldType.uint8),
    FieldSpec('flags', type: FieldType.uint24),
    FieldSpec('creation_time', type: FieldType.uint32),
    FieldSpec('modification_time', type: FieldType.uint32),
    FieldSpec('track_id', type: FieldType.uint32),
    FieldSpec('reserved', type: FieldType.uint32),
    FieldSpec('duration', type: FieldType.uint32),
    FieldSpec('reserved_1', type: FieldType.bytes, length: 8),
    FieldSpec('layer', type: FieldType.uint16),
    FieldSpec('alternate_group', type: FieldType.uint16),
    FieldSpec('volume', type: FieldType.uint16),
    FieldSpec('reserved_2', type: FieldType.uint16),
    FieldSpec('matrix', type: FieldType.bytes, length: 36),
    FieldSpec('width', type: FieldType.uint32),
    FieldSpec('height', type: FieldType.uint32),
  ],
);

/// `mdhd`（FullBox，version 0 布局）。
const ChildSpec _mdhdSpec = ChildSpec(
  type: 'mdhd',
  fields: [
    FieldSpec('version', type: FieldType.uint8),
    FieldSpec('flags', type: FieldType.uint24),
    FieldSpec('creation_time', type: FieldType.uint32),
    FieldSpec('modification_time', type: FieldType.uint32),
    FieldSpec('timescale', type: FieldType.uint32),
    FieldSpec('duration', type: FieldType.uint32),
    FieldSpec('language', type: FieldType.uint16),
    FieldSpec('pre_defined', type: FieldType.uint16),
  ],
);

/// `hdlr`（FullBox）。
const ChildSpec _hdlrSpec = ChildSpec(
  type: 'hdlr',
  fields: [
    FieldSpec('version', type: FieldType.uint8),
    FieldSpec('flags', type: FieldType.uint24),
    FieldSpec('pre_defined', type: FieldType.uint32),
    FieldSpec('handler_type', type: FieldType.fourcc),
    FieldSpec('reserved', type: FieldType.bytes, length: 12),
    FieldSpec('name', type: FieldType.utf8),
  ],
);

const ChildSpec _vmhdSpec = ChildSpec(
  type: 'vmhd',
  fields: [
    FieldSpec('version', type: FieldType.uint8),
    FieldSpec('flags', type: FieldType.uint24),
    FieldSpec('graphicsmode', type: FieldType.uint16),
    FieldSpec('opcolor', type: FieldType.bytes, length: 6),
  ],
);

const ChildSpec _smhdSpec = ChildSpec(
  type: 'smhd',
  fields: [
    FieldSpec('version', type: FieldType.uint8),
    FieldSpec('flags', type: FieldType.uint24),
    FieldSpec('balance', type: FieldType.sint16),
    FieldSpec('reserved', type: FieldType.uint16),
  ],
);

const ChildSpec _nmhdSpec = ChildSpec(
  type: 'nmhd',
  fields: [
    FieldSpec('version', type: FieldType.uint8),
    FieldSpec('flags', type: FieldType.uint24),
  ],
);

const ChildSpec _sthdSpec = ChildSpec(
  type: 'sthd',
  fields: [
    FieldSpec('version', type: FieldType.uint8),
    FieldSpec('flags', type: FieldType.uint24),
  ],
);

/// `dref`（FullBox）。它的载荷开头是 8 字节（version/flags + entry_count），
/// 之后才是 `url `/`urn ` 块——用 [HeaderRule.prefixBytes] 跳过。
const ChildSpec _drefSpec = ChildSpec(
  type: 'dref',
  container: _drefContainer,
  fields: [
    FieldSpec('version', type: FieldType.uint8),
    FieldSpec('flags', type: FieldType.uint24),
    FieldSpec('entry_count', type: FieldType.uint32),
  ],
);

/// `url `（数据引用条目）。载荷是 version/flags + 以 NUL 结尾的 location。
const ChildSpec _urlSpec = ChildSpec(
  type: 'url ',
  fields: [
    FieldSpec('version', type: FieldType.uint8),
    FieldSpec('flags', type: FieldType.uint24),
    FieldSpec('location', type: FieldType.utf8),
  ],
);

/// `elst`（FullBox）。条目是变长的（version 0 每条 12 字节，version 1 每条 20
/// 字节），表里读成字节串，由提取器按 version 解释。
const ChildSpec _elstSpec = ChildSpec(
  type: 'elst',
  fields: [
    FieldSpec('version', type: FieldType.uint8),
    FieldSpec('flags', type: FieldType.uint24),
    FieldSpec('entry_count', type: FieldType.uint32),
    FieldSpec('entries', type: FieldType.bytes),
  ],
);

// --- 采样表块 ---------------------------------------------------------------

/// `stsd`（FullBox）：版本/标志 + entry_count 之后是**动态类型**的 sample entry。
///
/// 引擎的 `dispatchOn` 语义：读完本块的字段后，用 `sample_entry_type` 的值去
/// **当前容器**（`stbl`）的子块表里查二级表，命中后继续读该二级表的字段。
/// 因此 sample entry 的字段被内联读进 `stsd` 这个节点。
const ChildSpec _stsdSpec = ChildSpec(
  type: 'stsd',
  dispatchOn: 'sample_entry_type',
  container: _stsdContainer,
  fields: [
    FieldSpec('version', type: FieldType.uint8),
    FieldSpec('flags', type: FieldType.uint24),
    FieldSpec('entry_count', type: FieldType.uint32),
    FieldSpec('sample_entry_size', type: FieldType.uint32),
    FieldSpec('sample_entry_type', type: FieldType.fourcc),
  ],
);

/// `stts`：条目是 (sample_count, sample_delta) 交错对，表里读成字节串，
/// 由提取器求和得出帧率。
const ChildSpec _sttsSpec = ChildSpec(
  type: 'stts',
  fields: [
    FieldSpec('version', type: FieldType.uint8),
    FieldSpec('flags', type: FieldType.uint24),
    FieldSpec('entry_count', type: FieldType.uint32),
    FieldSpec('entries', type: FieldType.bytes),
  ],
);

const ChildSpec _cttsSpec = ChildSpec(
  type: 'ctts',
  fields: [
    FieldSpec('version', type: FieldType.uint8),
    FieldSpec('flags', type: FieldType.uint24),
    FieldSpec('entry_count', type: FieldType.uint32),
    FieldSpec('entries', type: FieldType.bytes),
  ],
);

const ChildSpec _stssSpec = ChildSpec(
  type: 'stss',
  fields: [
    FieldSpec('version', type: FieldType.uint8),
    FieldSpec('flags', type: FieldType.uint24),
    FieldSpec('entry_count', type: FieldType.uint32),
    FieldSpec('entries', type: FieldType.bytes),
  ],
);

const ChildSpec _stscSpec = ChildSpec(
  type: 'stsc',
  fields: [
    FieldSpec('version', type: FieldType.uint8),
    FieldSpec('flags', type: FieldType.uint24),
    FieldSpec('entry_count', type: FieldType.uint32),
    FieldSpec('entries', type: FieldType.bytes),
  ],
);

/// `stsz`：sample_size != 0 时所有样本同大小，条目表是空的。
const ChildSpec _stszSpec = ChildSpec(
  type: 'stsz',
  fields: [
    FieldSpec('version', type: FieldType.uint8),
    FieldSpec('flags', type: FieldType.uint24),
    FieldSpec('sample_size', type: FieldType.uint32),
    FieldSpec('sample_count', type: FieldType.uint32),
    FieldSpec('entries', type: FieldType.bytes),
  ],
);

/// `stz2`：样本大小的位宽由载荷里的 `field_size` 决定（4/8/16），4 位时一个
/// 字节装两个值。表里只读出位宽，条目由提取器手写读取器解。
const ChildSpec _stz2Spec = ChildSpec(
  type: 'stz2',
  fields: [
    FieldSpec('version', type: FieldType.uint8),
    FieldSpec('flags', type: FieldType.uint24),
    FieldSpec('reserved', type: FieldType.bits, bitWidth: 24),
    FieldSpec('field_size', type: FieldType.uint8),
    FieldSpec('sample_count', type: FieldType.uint24),
    FieldSpec('entries', type: FieldType.bytes),
  ],
);

const ChildSpec _stcoSpec = ChildSpec(
  type: 'stco',
  fields: [
    FieldSpec('version', type: FieldType.uint8),
    FieldSpec('flags', type: FieldType.uint24),
    FieldSpec('entry_count', type: FieldType.uint32),
    FieldSpec('entries', type: FieldType.bytes),
  ],
);

const ChildSpec _co64Spec = ChildSpec(
  type: 'co64',
  fields: [
    FieldSpec('version', type: FieldType.uint8),
    FieldSpec('flags', type: FieldType.uint24),
    FieldSpec('entry_count', type: FieldType.uint32),
    FieldSpec('entries', type: FieldType.bytes),
  ],
);

const ChildSpec _sdtpSpec = ChildSpec(
  type: 'sdtp',
  fields: [
    FieldSpec('version', type: FieldType.uint8),
    FieldSpec('flags', type: FieldType.uint24),
    FieldSpec('entries', type: FieldType.bytes),
  ],
);

const ChildSpec _sbgpSpec = ChildSpec(
  type: 'sbgp',
  fields: [
    FieldSpec('version', type: FieldType.uint8),
    FieldSpec('flags', type: FieldType.uint24),
    FieldSpec('grouping_type', type: FieldType.fourcc),
    FieldSpec('grouping_type_parameter', type: FieldType.uint32),
    FieldSpec('entries', type: FieldType.bytes),
  ],
);

const ChildSpec _sgpdSpec = ChildSpec(
  type: 'sgpd',
  fields: [
    FieldSpec('version', type: FieldType.uint8),
    FieldSpec('flags', type: FieldType.uint24),
    FieldSpec('grouping_type', type: FieldType.fourcc),
    FieldSpec('grouping_type_parameter', type: FieldType.uint32),
    FieldSpec('default_length', type: FieldType.uint32),
    FieldSpec('entries', type: FieldType.bytes),
  ],
);

// --- sample entry（二级表） --------------------------------------------------

const ChildSpec _avc1Spec = ChildSpec(
  type: 'avc1',
  fields: _visualSampleEntryFields,
);
const ChildSpec _avc3Spec = ChildSpec(
  type: 'avc3',
  fields: _visualSampleEntryFields,
);
const ChildSpec _hvc1Spec = ChildSpec(
  type: 'hvc1',
  fields: _visualSampleEntryFields,
);
const ChildSpec _hev1Spec = ChildSpec(
  type: 'hev1',
  fields: _visualSampleEntryFields,
);
const ChildSpec _vp08Spec = ChildSpec(
  type: 'vp08',
  fields: _visualSampleEntryFields,
);
const ChildSpec _vp09Spec = ChildSpec(
  type: 'vp09',
  fields: _visualSampleEntryFields,
);
const ChildSpec _mp4vSpec = ChildSpec(
  type: 'mp4v',
  fields: _visualSampleEntryFields,
);
const ChildSpec _encvSpec = ChildSpec(
  type: 'encv',
  fields: _visualSampleEntryFields,
);
const ChildSpec _dvh1Spec = ChildSpec(
  type: 'dvh1',
  fields: _visualSampleEntryFields,
);
const ChildSpec _dvheSpec = ChildSpec(
  type: 'dvhe',
  fields: _visualSampleEntryFields,
);

const ChildSpec _mp4aSpec = ChildSpec(
  type: 'mp4a',
  fields: _audioSampleEntryFields,
);
const ChildSpec _mp4sSpec = ChildSpec(
  type: 'mp4s',
  fields: _audioSampleEntryFields,
);
const ChildSpec _encaSpec = ChildSpec(
  type: 'enca',
  fields: _audioSampleEntryFields,
);
const ChildSpec _ac3Spec = ChildSpec(
  type: 'ac-3',
  fields: _audioSampleEntryFields,
);
const ChildSpec _ec3Spec = ChildSpec(
  type: 'ec-3',
  fields: _audioSampleEntryFields,
);
const ChildSpec _opusSpec = ChildSpec(
  type: 'Opus',
  fields: _audioSampleEntryFields,
);
const ChildSpec _flacSpec = ChildSpec(
  type: 'fLaC',
  fields: _audioSampleEntryFields,
);
const ChildSpec _alacSpec = ChildSpec(
  type: 'alac',
  fields: _audioSampleEntryFields,
);
const ChildSpec _lpcmSpec = ChildSpec(
  type: 'lpcm',
  fields: _audioSampleEntryFields,
);
const ChildSpec _sowtSpec = ChildSpec(
  type: 'sowt',
  fields: _audioSampleEntryFields,
);
const ChildSpec _twosSpec = ChildSpec(
  type: 'twos',
  fields: _audioSampleEntryFields,
);
const ChildSpec _rawSpec = ChildSpec(
  type: 'raw ',
  fields: _audioSampleEntryFields,
);
const ChildSpec _in24Spec = ChildSpec(
  type: 'in24',
  fields: _audioSampleEntryFields,
);
const ChildSpec _in32Spec = ChildSpec(
  type: 'in32',
  fields: _audioSampleEntryFields,
);
const ChildSpec _fl32Spec = ChildSpec(
  type: 'fl32',
  fields: _audioSampleEntryFields,
);
const ChildSpec _fl64Spec = ChildSpec(
  type: 'fl64',
  fields: _audioSampleEntryFields,
);
const ChildSpec _ulawSpec = ChildSpec(
  type: 'ulaw',
  fields: _audioSampleEntryFields,
);
const ChildSpec _alawSpec = ChildSpec(
  type: 'alaw',
  fields: _audioSampleEntryFields,
);
const ChildSpec _ima4Spec = ChildSpec(
  type: 'ima4',
  fields: _audioSampleEntryFields,
);

/// sample entry 内部的编解码配置块——定义在别的规范里（14496-15 等），
/// 本 MVP 当**不透明叶子**，不做编码参数级字段。
const ChildSpec _avcCSpec = ChildSpec(type: 'avcC', opaque: true);
const ChildSpec _hvcCSpec = ChildSpec(type: 'hvcC', opaque: true);
const ChildSpec _esdsSpec = ChildSpec(type: 'esds', opaque: true);
const ChildSpec _colrSpec = ChildSpec(type: 'colr', opaque: true);
const ChildSpec _paspSpec = ChildSpec(type: 'pasp', opaque: true);
const ChildSpec _btrtSpec = ChildSpec(type: 'btrt', opaque: true);
const ChildSpec _waveSpec = ChildSpec(type: 'wave', opaque: true);

/// `dref` 里的数据引用条目（`url ` / `urn `）。
/// `urn `（数据引用条目）：载荷是 version/flags + 名字 + location。
const ChildSpec _urnSpec = ChildSpec(type: 'urn ', opaque: true);

// --- 不透明叶子 --------------------------------------------------------------

const ChildSpec _mdatSpec = ChildSpec(type: 'mdat', opaque: true);
const ChildSpec _freeSpec = ChildSpec(type: 'free', opaque: true);
const ChildSpec _skipSpec = ChildSpec(type: 'skip', opaque: true);
const ChildSpec _wideSpec = ChildSpec(type: 'wide', opaque: true);
const ChildSpec _uuidSpec = ChildSpec(type: 'uuid', opaque: true);
const ChildSpec _psshSpec = ChildSpec(type: 'pssh', opaque: true);
const ChildSpec _iodsSpec = ChildSpec(type: 'iods', opaque: true);
const ChildSpec _stypSpec = ChildSpec(type: 'styp', opaque: true);
const ChildSpec _sidxSpec = ChildSpec(type: 'sidx', opaque: true);
const ChildSpec _pnotSpec = ChildSpec(type: 'pnot', opaque: true);
const ChildSpec _pdinSpec = ChildSpec(type: 'pdin', opaque: true);
const ChildSpec _subsSpec = ChildSpec(type: 'subs', opaque: true);
const ChildSpec _saizSpec = ChildSpec(type: 'saiz', opaque: true);
const ChildSpec _saioSpec = ChildSpec(type: 'saio', opaque: true);
const ChildSpec _cslgSpec = ChildSpec(type: 'cslg', opaque: true);
const ChildSpec _elngSpec = ChildSpec(type: 'elng', opaque: true);
const ChildSpec _trefSpec = ChildSpec(type: 'tref', opaque: true);
const ChildSpec _taptSpec = ChildSpec(type: 'tapt', opaque: true);
const ChildSpec _metaSpec = ChildSpec(type: 'meta', opaque: true);
const ChildSpec _mfhdSpec = ChildSpec(type: 'mfhd', opaque: true);
const ChildSpec _tfhdSpec = ChildSpec(type: 'tfhd', opaque: true);
const ChildSpec _tfdtSpec = ChildSpec(type: 'tfdt', opaque: true);
const ChildSpec _trunSpec = ChildSpec(type: 'trun', opaque: true);

// --- 容器 -------------------------------------------------------------------

/// `stsd` 载荷的二级结构：sample entry 及其内部的编解码配置块。
///
/// 这张表目前只用于**声明**二级结构；sample entry 的字段由 `stsd` 的
/// `dispatchOn` 内联读出（引擎的分派语义：分派命中的二级表的字段接在分派块
/// 的字段之后读）。sample entry 自己**没有**成为结构树里的节点——它的载荷
/// 前面是长度随类型/版本变化的定长头（视觉 78 字节、音频 28 或 44 字节），
/// `HeaderRule.prefixBytes` 只能跳固定长度，跳不对就会读出假块。
const ContainerSpec _stsdContainer = ContainerSpec(
  name: 'stsd',
  header: _isoHeader,
  children: {
    'avc1': _avc1Spec,
    'avc3': _avc3Spec,
    'hvc1': _hvc1Spec,
    'hev1': _hev1Spec,
    'vp08': _vp08Spec,
    'vp09': _vp09Spec,
    'mp4v': _mp4vSpec,
    'encv': _encvSpec,
    'dvh1': _dvh1Spec,
    'dvhe': _dvheSpec,
    'mp4a': _mp4aSpec,
    'mp4s': _mp4sSpec,
    'enca': _encaSpec,
    'ac-3': _ac3Spec,
    'ec-3': _ec3Spec,
    'Opus': _opusSpec,
    'fLaC': _flacSpec,
    'alac': _alacSpec,
    'lpcm': _lpcmSpec,
    'sowt': _sowtSpec,
    'twos': _twosSpec,
    'raw ': _rawSpec,
    'in24': _in24Spec,
    'in32': _in32Spec,
    'fl32': _fl32Spec,
    'fl64': _fl64Spec,
    'ulaw': _ulawSpec,
    'alaw': _alawSpec,
    'ima4': _ima4Spec,
    'avcC': _avcCSpec,
    'hvcC': _hvcCSpec,
    'esds': _esdsSpec,
    'colr': _colrSpec,
    'pasp': _paspSpec,
    'btrt': _btrtSpec,
    'wave': _waveSpec,
  },
);

// --- 容器型子块 -------------------------------------------------------------

const ChildSpec _dinfChild = ChildSpec(type: 'dinf', container: _dinfContainer);
const ChildSpec _stblChild = ChildSpec(type: 'stbl', container: _stblContainer);
const ChildSpec _minfChild = ChildSpec(type: 'minf', container: _minfContainer);
const ChildSpec _mdiaChild = ChildSpec(type: 'mdia', container: _mdiaContainer);
const ChildSpec _edtsChild = ChildSpec(type: 'edts', container: _edtsContainer);
const ChildSpec _udtaChild = ChildSpec(type: 'udta', container: _udtaContainer);
const ChildSpec _trakChild = ChildSpec(type: 'trak', container: _trakContainer);
const ChildSpec _trafChild = ChildSpec(type: 'traf', container: _trafContainer);
const ChildSpec _moofChild = ChildSpec(type: 'moof', container: _moofContainer);
const ChildSpec _moovChild = ChildSpec(type: 'moov', container: _moovContainer);

/// `stbl`（采样表）。
///
/// 这里同时挂着 sample entry 的二级表：`dispatchOn` 在**当前容器**的子块表里
/// 查找，而 `stsd` 属于 `stbl`，所以二级表必须出现在 `stbl` 的表里。
const ContainerSpec _stblContainer = ContainerSpec(
  name: 'stbl',
  header: _isoHeader,
  children: {
    'stsd': _stsdSpec,
    'stts': _sttsSpec,
    'ctts': _cttsSpec,
    'stss': _stssSpec,
    'stsc': _stscSpec,
    'stsz': _stszSpec,
    'stz2': _stz2Spec,
    'stco': _stcoSpec,
    'co64': _co64Spec,
    'sdtp': _sdtpSpec,
    'sbgp': _sbgpSpec,
    'sgpd': _sgpdSpec,
    'subs': _subsSpec,
    'saiz': _saizSpec,
    'saio': _saioSpec,
    'cslg': _cslgSpec,
    // 二级表：动态类型的 sample entry（供 `stsd` 的 dispatchOn 查找）。
    'avc1': _avc1Spec,
    'avc3': _avc3Spec,
    'hvc1': _hvc1Spec,
    'hev1': _hev1Spec,
    'vp08': _vp08Spec,
    'vp09': _vp09Spec,
    'mp4v': _mp4vSpec,
    'encv': _encvSpec,
    'dvh1': _dvh1Spec,
    'dvhe': _dvheSpec,
    'mp4a': _mp4aSpec,
    'mp4s': _mp4sSpec,
    'enca': _encaSpec,
    'ac-3': _ac3Spec,
    'ec-3': _ec3Spec,
    'Opus': _opusSpec,
    'fLaC': _flacSpec,
    'alac': _alacSpec,
    'lpcm': _lpcmSpec,
    'sowt': _sowtSpec,
    'twos': _twosSpec,
    'raw ': _rawSpec,
    'in24': _in24Spec,
    'in32': _in32Spec,
    'fl32': _fl32Spec,
    'fl64': _fl64Spec,
    'ulaw': _ulawSpec,
    'alaw': _alawSpec,
    'ima4': _ima4Spec,
  },
);

/// `dinf`（数据引用）。`dref` 内部的 `url `/`urn ` 块在 [_drefContainer] 里展开。
const ContainerSpec _dinfContainer = ContainerSpec(
  name: 'dinf',
  header: _isoHeader,
  children: {'dref': _drefSpec},
);

/// `dref` 的载荷容器：开头 8 字节是 version/flags + entry_count，跳过才是子块。
const ContainerSpec _drefContainer = ContainerSpec(
  name: 'dref',
  header: _drefHeader,
  children: {'url ': _urlSpec, 'urn ': _urnSpec},
);

const ContainerSpec _minfContainer = ContainerSpec(
  name: 'minf',
  header: _isoHeader,
  children: {
    'vmhd': _vmhdSpec,
    'smhd': _smhdSpec,
    'nmhd': _nmhdSpec,
    'sthd': _sthdSpec,
    'dinf': _dinfChild,
    'stbl': _stblChild,
  },
);

const ContainerSpec _mdiaContainer = ContainerSpec(
  name: 'mdia',
  header: _isoHeader,
  children: {
    'mdhd': _mdhdSpec,
    'hdlr': _hdlrSpec,
    'minf': _minfChild,
    'elng': _elngSpec,
  },
);

const ContainerSpec _edtsContainer = ContainerSpec(
  name: 'edts',
  header: _isoHeader,
  children: {'elst': _elstSpec},
);

const ContainerSpec _udtaContainer = ContainerSpec(
  name: 'udta',
  header: _isoHeader,
  children: {'meta': _metaSpec},
);

const ContainerSpec _trakContainer = ContainerSpec(
  name: 'trak',
  header: _isoHeader,
  children: {
    'tkhd': _tkhdSpec,
    'tref': _trefSpec,
    'edts': _edtsChild,
    'mdia': _mdiaChild,
    'udta': _udtaChild,
    'tapt': _taptSpec,
  },
);

const ContainerSpec _trafContainer = ContainerSpec(
  name: 'traf',
  header: _isoHeader,
  children: {'tfhd': _tfhdSpec, 'tfdt': _tfdtSpec, 'trun': _trunSpec},
);

const ContainerSpec _moofContainer = ContainerSpec(
  name: 'moof',
  header: _isoHeader,
  children: {'mfhd': _mfhdSpec, 'traf': _trafChild},
);

const ContainerSpec _moovContainer = ContainerSpec(
  name: 'moov',
  header: _isoHeader,
  children: {
    'mvhd': _mvhdSpec,
    'trak': _trakChild,
    'udta': _udtaChild,
    'meta': _metaSpec,
    'pssh': _psshSpec,
    'iods': _iodsSpec,
  },
);

/// ISO BMFF（MP4 / MOV）的容器规格表。
///
/// 根节点 = 整个文件；根节点的子块就是文件里的顶层块（`ftyp`/`moov`/`mdat`…）。
const ContainerSpec isoBmffContainer = ContainerSpec(
  name: 'MP4',
  rootType: 'MP4',
  header: _isoHeader,
  children: {
    'ftyp': _ftypSpec,
    'styp': _stypSpec,
    'moov': _moovChild,
    'moof': _moofChild,
    'mdat': _mdatSpec,
    'free': _freeSpec,
    'skip': _skipSpec,
    'wide': _wideSpec,
    'uuid': _uuidSpec,
    'meta': _metaSpec,
    'pssh': _psshSpec,
    'sidx': _sidxSpec,
    'pnot': _pnotSpec,
    'pdin': _pdinSpec,
  },
);

// ---------------------------------------------------------------------------
// 叶子提取器
// ---------------------------------------------------------------------------

/// ISO BMFF（MP4 / MOV）的叶子提取器。
///
/// 文件级字段挂在根节点上，轨道级字段挂在对应的 `trak` 节点上——本函数返回
/// 的是一张扁平的字段表，用 [FieldScope] 与 [SemanticField.trackIndex] 区分
/// 归属（轨道序号 = `moov` 里 `trak` 的出现顺序，从 0 开始）。
List<SemanticField> extractIsoBmffFields(ContainerNode root) {
  final fields = <SemanticField>[];

  final moov = _childOf(root, 'moov');
  final mvhd = _childOf(moov, 'mvhd');
  final movieTimescale = _intFieldOf(mvhd, 'timescale');
  final movieDuration = _intFieldOf(mvhd, 'duration');

  // --- 文件级 ---
  final ftyp = _childOf(root, 'ftyp');
  final brand = _stringFieldOf(ftyp, 'major_brand');
  if (brand != null) {
    fields.add(_fileField('brand', '主品牌', brand, source: 'ftyp'));
  }
  final compatible = _bytesFieldOf(ftyp, 'compatible_brands');
  if (compatible != null) {
    fields.add(
      _fileField(
        'compatible_brands',
        '兼容品牌',
        _fourccList(compatible),
        source: 'ftyp',
      ),
    );
  }

  double? fileDuration;
  if (movieTimescale != null &&
      movieTimescale > 0 &&
      movieDuration != null &&
      _versionOf(mvhd) == 0) {
    fileDuration = movieDuration / movieTimescale;
    fields.add(
      _fileField('duration', '时长', fileDuration, unit: 's', source: 'mvhd'),
    );
    fields.add(
      _fileField(
        'timescale',
        '时间刻度',
        movieTimescale,
        unit: 'tick',
        source: 'mvhd',
      ),
    );
  }
  if (fileDuration != null && fileDuration > 0) {
    fields.add(
      SemanticField(
        key: 'overall_bitrate',
        label: '平均码率',
        value: root.size * 8 / fileDuration,
        unit: 'bit/s',
        origin: FieldOrigin.derived,
        scope: FieldScope.file,
        source: 'mvhd',
      ),
    );
  }

  // --- 轨道级 ---
  final traks = _childrenOf(moov, 'trak');
  for (var index = 0; index < traks.length; index++) {
    fields.addAll(_trackFields(traks[index], index, movieTimescale));
  }

  return fields;
}

/// 取一条轨道的语义字段。
List<SemanticField> _trackFields(
  ContainerNode trak,
  int index,
  int? movieTimescale,
) {
  final out = <SemanticField>[];

  final tkhd = _childOf(trak, 'tkhd');
  final mdia = _childOf(trak, 'mdia');
  final mdhd = _childOf(mdia, 'mdhd');
  final hdlr = _childOf(mdia, 'hdlr');
  final minf = _childOf(mdia, 'minf');
  final stbl = _childOf(minf, 'stbl');
  final stsd = _childOf(stbl, 'stsd');
  final elst = _childOf(_childOf(trak, 'edts'), 'elst');

  final handlerType = _stringFieldOf(hdlr, 'handler_type');
  final trackType = handlerType == null ? null : _trackTypeOf(handlerType);
  final codec = _stringFieldOf(stsd, 'sample_entry_type');

  out.add(
    _trackField('track_index', '轨道序号', index, index: index, source: 'trak'),
  );
  if (trackType != null) {
    out.add(
      _trackField(
        'track_type',
        '轨道类型',
        trackType,
        index: index,
        source: 'hdlr',
      ),
    );
  }
  if (handlerType != null) {
    out.add(
      _trackField(
        'handler_type',
        '处理器类型',
        handlerType,
        index: index,
        source: 'hdlr',
      ),
    );
  }
  if (codec != null) {
    out.add(_trackField('codec', '编码标识', codec, index: index, source: 'stsd'));
  }

  // 分辨率：优先用 `tkhd` 的显示尺寸（16.16 定点），退回 sample entry 的存尺寸。
  final width =
      _fixed1616(_intFieldOf(tkhd, 'width')) ?? _intFieldOf(stsd, 'width');
  final height =
      _fixed1616(_intFieldOf(tkhd, 'height')) ?? _intFieldOf(stsd, 'height');
  if (width != null && width > 0) {
    out.add(
      _trackField(
        'width',
        '宽度',
        width,
        unit: 'px',
        index: index,
        source: 'tkhd',
      ),
    );
  }
  if (height != null && height > 0) {
    out.add(
      _trackField(
        'height',
        '高度',
        height,
        unit: 'px',
        index: index,
        source: 'tkhd',
      ),
    );
  }

  // 音频参数：来自 sample entry。
  final sampleRate = _fixed1616(_intFieldOf(stsd, 'samplerate'));
  if (sampleRate != null && sampleRate > 0) {
    out.add(
      _trackField(
        'sample_rate',
        '采样率',
        sampleRate,
        unit: 'Hz',
        index: index,
        source: 'stsd',
      ),
    );
  }
  final channels = _intFieldOf(stsd, 'channelcount');
  if (channels != null && channels > 0) {
    out.add(
      _trackField('channels', '声道数', channels, index: index, source: 'stsd'),
    );
  }
  final bitDepth = _intFieldOf(stsd, 'samplesize');
  if (bitDepth != null && bitDepth > 0) {
    out.add(
      _trackField(
        'bit_depth',
        '位深',
        bitDepth,
        unit: 'bit',
        index: index,
        source: 'stsd',
      ),
    );
  }

  // 帧率：`stts` 的样本数 ÷ 时长（媒体时间刻度）。
  final isVideo =
      trackType == 'video' ||
      (trackType == null && _intFieldOf(stsd, 'width') != null);
  final mediaTimescale = _intFieldOf(mdhd, 'timescale');
  if (isVideo) {
    final frameRate = _frameRateOf(stbl, mediaTimescale);
    if (frameRate != null) {
      out.add(
        _trackField(
          'frame_rate',
          '帧率',
          frameRate,
          unit: 'fps',
          index: index,
          source: 'stts',
        ),
      );
    }
  }

  // 语言：`mdhd` 的 3 个 5 位字母（packed 15 bit）。
  final language = _intFieldOf(mdhd, 'language');
  if (language != null && language != 0) {
    out.add(
      _trackField(
        'language',
        '语言',
        _decodeLanguage(language),
        index: index,
        source: 'mdhd',
      ),
    );
  }

  // 轨道时长：剪辑表（`elst`）优先，退回 `mdhd` 的媒体时长。
  final editDuration = _editDurationOf(elst, movieTimescale);
  double? trackDuration = editDuration;
  final mediaDuration = _intFieldOf(mdhd, 'duration');
  if (trackDuration == null &&
      mediaDuration != null &&
      mediaTimescale != null &&
      mediaTimescale > 0) {
    trackDuration = mediaDuration / mediaTimescale;
  }
  if (trackDuration != null) {
    out.add(
      _trackField(
        'duration',
        '时长',
        trackDuration,
        unit: 's',
        index: index,
        source: editDuration != null ? 'elst' : 'mdhd',
      ),
    );
  }

  if (mediaTimescale != null && mediaTimescale > 0) {
    out.add(
      _trackField(
        'media_timescale',
        '媒体时间刻度',
        mediaTimescale,
        unit: 'tick',
        index: index,
        source: 'mdhd',
      ),
    );
  }
  final trackId = _intFieldOf(tkhd, 'track_id');
  if (trackId != null) {
    out.add(
      _trackField('track_id', '轨道 ID', trackId, index: index, source: 'tkhd'),
    );
  }

  // 编码器名字（sample entry 的 32 字节定长串，首字节是实际长度）。
  final compressor = _bytesFieldOf(stsd, 'compressorname');
  if (compressor != null) {
    final name = _decodeCompressorName(compressor);
    if (name.isNotEmpty) {
      out.add(
        _trackField(
          'compressorname',
          '编码器',
          name,
          index: index,
          source: 'stsd',
        ),
      );
    }
  }

  // 样本数量与总字节数（`stsz` / `stz2`）。
  final stsz = _childOf(stbl, 'stsz');
  final stz2 = _childOf(stbl, 'stz2');
  if (stsz != null) {
    final count = _intFieldOf(stsz, 'sample_count');
    final sizes = _stszSizes(
      _intFieldOf(stsz, 'sample_size') ?? 0,
      count ?? 0,
      _bytesFieldOf(stsz, 'entries'),
    );
    if (count != null) {
      out.add(
        _trackField('sample_count', '样本数', count, index: index, source: 'stsz'),
      );
    }
    if (sizes.isNotEmpty) {
      out.add(
        _trackField(
          'sample_size_total',
          '样本总字节',
          sizes.fold<int>(0, (sum, size) => sum + size),
          unit: 'byte',
          index: index,
          source: 'stsz',
        ),
      );
    }
  } else if (stz2 != null) {
    final count = _intFieldOf(stz2, 'sample_count');
    final fieldSize = _intFieldOf(stz2, 'field_size');
    final sizes = _stz2Sizes(
      fieldSize ?? 0,
      count ?? 0,
      _bytesFieldOf(stz2, 'entries'),
    );
    if (count != null) {
      out.add(
        _trackField('sample_count', '样本数', count, index: index, source: 'stz2'),
      );
    }
    if (fieldSize != null && fieldSize > 0) {
      out.add(
        _trackField(
          'sample_size_field',
          '样本大小位宽',
          fieldSize,
          unit: 'bit',
          index: index,
          source: 'stz2',
        ),
      );
    }
    if (sizes.isNotEmpty) {
      out.add(
        _trackField(
          'sample_size_total',
          '样本总字节',
          sizes.fold<int>(0, (sum, size) => sum + size),
          unit: 'byte',
          index: index,
          source: 'stz2',
        ),
      );
    }
  }

  return out;
}

// ---------------------------------------------------------------------------
// 提取器内部工具
// ---------------------------------------------------------------------------

/// 找第一个类型为 [type] 的子块。
ContainerNode? _childOf(ContainerNode? node, String type) {
  if (node == null) return null;
  for (final child in node.children) {
    if (child.type == type) return child;
  }
  return null;
}

/// 找所有类型为 [type] 的子块。
List<ContainerNode> _childrenOf(ContainerNode? node, String type) {
  if (node == null) return const [];
  return node.children.where((child) => child.type == type).toList();
}

/// 取整数字段的值。
int? _intFieldOf(ContainerNode? node, String key) {
  if (node == null) return null;
  for (final field in node.fields) {
    if (field.key != key) continue;
    final value = field.value;
    if (value is int) return value;
  }
  return null;
}

/// 取字符串字段的值。
String? _stringFieldOf(ContainerNode? node, String key) {
  if (node == null) return null;
  for (final field in node.fields) {
    if (field.key != key) continue;
    final value = field.value;
    if (value is String) return value;
  }
  return null;
}

/// 取字节串字段的值。
Uint8List? _bytesFieldOf(ContainerNode? node, String key) {
  if (node == null) return null;
  for (final field in node.fields) {
    if (field.key != key) continue;
    final value = field.value;
    if (value is Uint8List) return value;
  }
  return null;
}

/// 取块头的 version（`FullBox` 的第一个字节）。
int? _versionOf(ContainerNode? node) => _intFieldOf(node, 'version');

/// 16.16 定点数 → 整数。
int? _fixed1616(int? value) => value == null ? null : (value >> 16) & 0xFFFF;

/// 把 4 字节一组拆成 fourcc 列表。
List<String> _fourccList(Uint8List bytes) {
  final out = <String>[];
  for (var i = 0; i + 4 <= bytes.length; i += 4) {
    out.add(String.fromCharCodes(bytes.sublist(i, i + 4)));
  }
  return out;
}

/// `hdlr` 的 handler_type → 统一词表里的轨道类型。
String _trackTypeOf(String handlerType) {
  switch (handlerType) {
    case 'vide':
      return 'video';
    case 'soun':
      return 'audio';
    case 'sbtl':
    case 'subp':
    case 'text':
      return 'subtitle';
    case 'hint':
      return 'hint';
    case 'meta':
      return 'metadata';
    case 'clcp':
    case 'cleg':
      return 'closed_caption';
    default:
      return 'other';
  }
}

/// `mdhd` 的 15 位打包语言码 → 三字母代码（ISO 639-2）。
String _decodeLanguage(int packed) {
  if (packed == 0x7FFF) return 'und'; // 规范里的"未定义"
  final c1 = ((packed >> 10) & 0x1F) + 0x60;
  final c2 = ((packed >> 5) & 0x1F) + 0x60;
  final c3 = (packed & 0x1F) + 0x60;
  return String.fromCharCodes([c1, c2, c3]);
}

/// sample entry 的 32 字节定长串：首字节是实际长度。
String _decodeCompressorName(Uint8List bytes) {
  if (bytes.isEmpty) return '';
  final length = bytes[0];
  if (length == 0 || length > bytes.length - 1) return '';
  return String.fromCharCodes(bytes.sublist(1, length + 1)).trim();
}

/// `stts` → 帧率（样本数 ÷ 该轨道的时间跨度）。
double? _frameRateOf(ContainerNode? stbl, int? mediaTimescale) {
  if (mediaTimescale == null || mediaTimescale <= 0) return null;
  final stts = _childOf(stbl, 'stts');
  final entryCount = _intFieldOf(stts, 'entry_count');
  final entries = _bytesFieldOf(stts, 'entries');
  if (entryCount == null || entries == null) return null;

  var samples = 0;
  var delta = 0;
  for (var i = 0; i < entryCount; i++) {
    final offset = i * 8;
    if (offset + 8 > entries.length) break;
    final count = _readU32(entries, offset);
    final sampleDelta = _readU32(entries, offset + 4);
    samples += count;
    delta += count * sampleDelta;
  }
  if (samples <= 0 || delta <= 0) return null;
  return samples * mediaTimescale / delta;
}

/// `elst` → 剪辑时长（秒，影片时间刻度）。
double? _editDurationOf(ContainerNode? elst, int? movieTimescale) {
  if (movieTimescale == null || movieTimescale <= 0) return null;
  final entryCount = _intFieldOf(elst, 'entry_count');
  final entries = _bytesFieldOf(elst, 'entries');
  if (entryCount == null || entries == null) return null;

  final version = _versionOf(elst) ?? 0;
  final entrySize = version == 0 ? 12 : 20;
  var total = 0;
  for (var i = 0; i < entryCount; i++) {
    final offset = i * entrySize;
    if (offset + entrySize > entries.length) break;
    total += version == 0
        ? _readU32(entries, offset)
        : _readU64(entries, offset);
  }
  if (total <= 0) return null;
  return total / movieTimescale;
}

/// `stsz` 的样本大小表。
List<int> _stszSizes(int sampleSize, int count, Uint8List? entries) {
  if (sampleSize != 0) {
    return List<int>.filled(count, sampleSize);
  }
  if (entries == null) return const [];
  final sizes = <int>[];
  for (var i = 0; i < count && i * 4 + 3 < entries.length; i++) {
    sizes.add(_readU32(entries, i * 4));
  }
  return sizes;
}

/// `stz2` 的样本大小表：位宽由载荷决定（4/8/16），4 位时一个字节装两个值。
List<int> _stz2Sizes(int fieldSize, int count, Uint8List? entries) {
  if (entries == null) return const [];
  final sizes = <int>[];
  switch (fieldSize) {
    case 4:
      for (var i = 0; i < count; i++) {
        final index = i ~/ 2;
        if (index >= entries.length) break;
        final byte = entries[index];
        sizes.add(i.isEven ? (byte >> 4) & 0x0F : byte & 0x0F);
      }
    case 8:
      for (var i = 0; i < count && i < entries.length; i++) {
        sizes.add(entries[i]);
      }
    case 16:
      for (var i = 0; i < count && i * 2 + 1 < entries.length; i++) {
        sizes.add(_readU16(entries, i * 2));
      }
    default:
      // field_size == 0：大小在 `stsz` 里，这里没有可读的内容。
      break;
  }
  return sizes;
}

int _readU16(Uint8List data, int offset) =>
    (data[offset] << 8) | data[offset + 1];

int _readU32(Uint8List data, int offset) =>
    (data[offset] << 24) |
    (data[offset + 1] << 16) |
    (data[offset + 2] << 8) |
    data[offset + 3];

int _readU64(Uint8List data, int offset) {
  var value = 0;
  for (var i = 0; i < 8; i++) {
    value = (value << 8) | data[offset + i];
  }
  return value;
}

/// 构造一个文件级语义字段。
SemanticField _fileField(
  String key,
  String label,
  Object? value, {
  String? unit,
  FieldOrigin origin = FieldOrigin.read,
  String? source,
}) {
  return SemanticField(
    key: key,
    label: label,
    value: value,
    unit: unit,
    origin: origin,
    scope: FieldScope.file,
    source: source,
  );
}

/// 构造一个轨道级语义字段。
SemanticField _trackField(
  String key,
  String label,
  Object? value, {
  String? unit,
  FieldOrigin origin = FieldOrigin.read,
  required int index,
  String? source,
}) {
  return SemanticField(
    key: key,
    label: label,
    value: value,
    unit: unit,
    origin: origin,
    scope: FieldScope.track,
    trackIndex: index,
    source: source,
  );
}

// ---------------------------------------------------------------------------
// 格式注册
// ---------------------------------------------------------------------------

/// 嗅探：走一遍顶层 box 链，看有没有 ISO base media 的特征盒。
///
/// **不能只看偏移 4 是不是 `ftyp`**——真实世界的文件有好几种开头：
/// - `ftyp` —— 常规 MP4 / MOV（ffmpeg 与多数 muxer 的写法）
/// - `styp` / `moof` / `sidx` —— 分片 MP4（fMP4）
/// - `moov` —— 传统 QuickTime 常见开头
/// - `wide` —— QuickTime 的填充盒
/// - `mdat` —— 媒体数据在最前面的 MOV
///
/// 只看文件头，不参与扩展名判定——扩展名写成 `.wav` 的 MP4 也认。
bool _detectIsoBmff(ByteSource source) {
  if (source.length < 8) return false;

  // 只认这些顶层盒类型。`ftyp`/`styp`/`sidx`/`moof` 是 ISO base media 独有的；
  // `moov`/`mdat`/`wide` 是 QuickTime/MP4 常见开头。
  const signatureBoxes = {
    'ftyp',
    'styp',
    'sidx',
    'moof',
    'moov',
    'mdat',
    'wide',
  };

  const maxBoxesToWalk = 8;
  var offset = 0;
  for (var i = 0; i < maxBoxesToWalk; i++) {
    if (offset + 8 > source.length) return false;

    final Uint8List header = source.read(offset, 8);
    final int size = _readU32(header, 0);
    final String type = String.fromCharCodes(header.sublist(4, 8));

    if (signatureBoxes.contains(type)) {
      // 长度字段只做**最低限度的合理性校验**：
      // - 小于 8 的长度连块头都装不下，荒谬
      // - 0xFFFFFFFF 在 ISO BMFF 里不是"未知长度"（那是 size==0），在这里等于
      //   声明一个 4GB 的盒子，与文件大小对不上，多半是误判
      // 反过来，**声明长度超出文件末尾是允许的**——被截断的 MP4/MOV 非常常见，
      // 不能因为文件短就否认它是 ISO base media。
      if (size == 1) {
        if (offset + 16 > source.length) return false;
        final int largeSize = _readU64(source.read(offset + 8, 8), 0);
        if (largeSize < 16) return false;
      } else if (size != 0 && (size < 8 || size == 0xFFFFFFFF)) {
        return false;
      }
      return true;
    }

    // 推进到下一个顶层 box。
    final int next;
    if (size == 1) {
      if (offset + 16 > source.length) return false;
      final int largeSize = _readU64(source.read(offset + 8, 8), 0);
      if (largeSize < 16) return false;
      next = offset + largeSize;
    } else if (size == 0) {
      // 长度 0 = 这个 box 延伸到文件尾，后面不会再有顶层 box。
      return false;
    } else {
      if (size < 8) return false;
      next = offset + size;
    }
    if (next <= offset || next > source.length) return false;
    offset = next;
  }
  return false;
}

/// ISO BMFF（MP4 / MOV）的格式规格（供注册表登记）。
///
/// MOV 也用它，靠 `ftyp` 里的 brand 区分。
FormatSpec get mp4Format => FormatSpec(
  name: 'MP4',
  container: isoBmffContainer,
  extractor: extractIsoBmffFields,
  detect: _detectIsoBmff,
);

/// 把 ISO BMFF（MP4 / MOV）登记到全局注册表。
void registerMp4() => registerFormat(mp4Format);
