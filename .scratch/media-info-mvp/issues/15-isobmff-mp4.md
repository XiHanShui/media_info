# ISO BMFF（MP4 / MOV）：规格表 + 叶子提取器

Status: resolved
Blocked by: 13

## Question / 任务

**模块导出约定**：创建 `lib/src/formats/isobmff.dart`，导出 `FormatSpec get mp4Format`（MOV 也用它，用 brand 区分）、`void registerMp4()`。**不要在 import 时做注册副作用**，也不要创建 `all_formats.dart`（那是实现票 20 的统一入口）。

实现 **ISO base media file format**（MP4 / MOV）的规格表与语义字段提取。这是**四种格式里最复杂的一个**。

**必读**：`docs/design/core-api.md`、[调研 02](../../docs/research/02-declarative-parsers.md) §1.1 与 §4（不规则点清单）、[调研 03](../../docs/research/03-mediainfo-ffprobe-depth.md) §C.3。

**规格表**（`lib/src/formats/isobmff.dart`）：

- 块头：`size`(u32) + `type`(fourcc)；`size == 1` → 随后 u64 `largesize`；`size == 0` → 到文件尾。容器型 box 递归。
- `FullBox` 类（`moov`/`trak`/`mdia`/`minf`/`stbl` 下的多数）带 `version`(u8) + `flags`(24 bit)。
- 层级按规范 Table 1 建模：`ftyp`/`moov`/`trak`/`mdia`/`minf`/`stbl`/`stsd`/`stts`/`stsc`/`stsz`/`stco`/`co64`/`mdat`/`free`/`skip`/`uuid`/`mvhd`/`tkhd`/`mdhd`/`hdlr`/`vmhd`/`smhd`/`dref`/`url `/`elst`/`edts` 等。
- **必须留手写逃生口**（表表达不了或跨规范）：
  - `stsd` 的 sample entry 类型是**动态**的（`avc1`/`mp4a`/`hev1`…）→ 用 `dispatchOn` 做二级表分派。
  - `stz2` 的样本大小位宽由载荷决定（4/8/16，4 位时半字节打包）→ 运行期定宽数组。
  - `avcC`/`hvcC`/`esds` 定义在 14496-15 而非 14496-12 → 本 MVP 当**不透明叶子**即可（不做编码参数级字段）。
  - `colr` 按 `colour_type` 分派的变长载荷 → 不透明叶子。

**叶子提取器**：产出统一词表里的字段——`duration`（`mvhd`/`tkhd`/`mdhd` 的 timescale+duration）、`codec`（sample entry 的 fourcc）、`width`/`height`（`tkhd` 变换后的显示尺寸）、`frame_rate`（`stts` 的样本数/时长）、`track_type`（`hdlr`）、`language`（`mdhd`）、`overall_bitrate`（derived）。轨道级字段挂在对应 `trak` 节点上。

**测试**（`test/formats/isobmff_test.dart`）：用 `test/fixtures/mp4_h264_aac_320x240.normal.mp4`、`mp4_h264_noaudio_320x240.edge.mp4`、`mp4_h264_aac_320x240.normal.truncated.mp4`、`mov_mpeg4_aac_320x240.normal.mov`、`mov_mpeg4_aac_320x240.normal.truncated.mov`。

**块覆盖率清单**断言：至少能找到 `ftyp`/`moov`/`trak`/`mdia`/`minf`/`stbl`/`stsd`/`mdat`/`free`/`skip`（`uuid` 若样本里没有则跳过该条）。

**格式嗅探（本票必须实现）**：本格式要实现自己的 `detect` 回调并随 `FormatSpec` 一起注册。嗅探**只看文件头**，不参与扩展名判定：

- WAV：偏移 0 是 `RIFF`，偏移 8 是 `WAVE`
- AIFF：偏移 0 是 `FORM`，偏移 8 是 `AIFF`
- FLAC：偏移 0 是 `fLaC`
- MP4 / MOV：偏移 4 是 `ftyp`
- Matroska / WebM：偏移 0 是 `1A 45 DF A3`
- MP3：偏移 0 是 `ID3`，或帧同步 `0xFF Ex/Fx`

注册方式：`registerFormat(FormatSpec(name: ..., container: ..., extractor: ..., detect: ...))`，**从你自己的文件里调用，不要改 `lib/src/core/registry.dart`**（并行合并冲突的高发点）。注册顺序即嗅探顺序。

**扩展名不符也要能正确识别**：测试里把本格式的样本复制成**错误的扩展名**（例如 `mislabelled.wav`）到临时目录，断言 `detectFormat` 仍返回本格式。

**约束**：纯 Dart，无新依赖。`flutter analyze` 无 issue。

## Answer

已实现并合并进 `integration/media-info-mvp`。公开 API：`isoBmffContainer`（规格表，rootType = `'MP4'`）、`extractIsoBmffFields(root)`、`mp4Format`（含 `detect`）、`registerMp4()`。

**规格表要点**：`sizeFirst: true`（size 在 type 之前）、`sizeIncludesHeader: true`、`sizeZeroMeansToEof: true`、`extendedSizeWhenOne: true`（`largesize`）。`dref` 额外用 `prefixBytes: 8` 跳过 version/flags + entry_count，于是 `dref > url ` 能进树。`stsd` 用 `dispatchOn: 'sample_entry_type'` 做动态分派——**二级表必须复制到当前容器（`stbl`）的 children map 里**，因为引擎的 dispatch 先查 `scopes[0]`。

**三个需要下游知道的限制**：

1. **sample entry 不是独立的树节点**。引擎的 dispatch 语义是：二级表的字段被读进**分派者（`stsd`）那个节点**。所以 `avcC`/`hvcC`/`esds`/`colr` 虽然在表里声明为不透明叶子，**它们不会出现在树里**。原因是 sample entry 的载荷头长度随 type/version 变（visual 78 B、audio 28 B ISO / 44 B QuickTime-v1），`prefixBytes` 是定长的，跳不过去。
2. **`mvhd`/`tkhd`/`mdhd` 只按 version-0 布局解析**。引擎没有"按 version 决定字段宽度"的能力，所以 version==1 时提取器**主动丢弃** duration/timescale 相关字段，而不是输出垃圾值。
3. **`stts`/`stsz`/`stz2`/`stsc`/`stco`/`elst` 的载荷体是 `bytes` 字段**（`Uint8List` 装在 `SemanticField.value` 里），由提取器手写读取器解码——引擎表达不了交织数组和运行期位宽。`stz2` 的 4/8/16 位宽（含半字节打包）有专门的合成文件测试。

**解析深度**：完整 MP4 树需要 `depth >= 6`（root→moov→trak→mdia→minf→stbl→stsd），测试用 `depth: 8`。提取器不重读字节，只看节点树，所以依赖这个深度。

**轨道时长**取 `elst` 的 segment duration ÷ movie timescale（与 ffprobe 一致：视频 1.0 s、音频 0.25 s），回退到 `mdhd` duration ÷ `mdhd` timescale。

**格式名**：MOV 也叫 `'MP4'`，靠 `ftyp` 的 brand 区分（`brand` / `compatible_brands` 字段已产出）。`detect` 只看偏移 4 是不是 `ftyp`——**没有 `ftyp` 的传统 QuickTime 文件不会被识别**。

**验证**：`flutter analyze` 无 issue；`flutter test` 118 个全过（本票新增 13 个）；`dart format` 已应用。
