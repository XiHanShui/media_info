# Matroska / WebM：规格表 + 叶子提取器

Status: ready-for-agent
Blocked by: 13

## Question / 任务

**模块导出约定**：创建 `lib/src/formats/matroska.dart`，导出 `FormatSpec get matroskaFormat`（WebM 也它，用 docType 区分）、`void registerMatroska()`。**不要在 import 时做注册副作用**，也不要创建 `all_formats.dart`（那是实现票 20 的统一入口）。

实现 **Matroska / WebM**（EBML）的规格表与语义字段提取。

**必读**：`docs/design/core-api.md`、[调研 02](../../docs/research/02-declarative-parsers.md) §1.2 与 §4（EBML 不规则点）。

**规格表**（`lib/src/formats/matroska.dart`）：

- EBML 头：`id`（VINT）+ `size`（VINT）。`size` 可以是"未知长度"哨兵 → `unknownSizeAllowed = true`，收尾靠**路径**判定（`Segment` 用下一个同级元素或 EOF 收尾）。
- **官方 schema 已经以机器可读形式发布**：`ebml_matroska.xml`（<https://raw.githubusercontent.com/ietf-wg-cellar/matroska-specification/master/ebml_matroska.xml>，262 个元素 / 49 个 master 元素）。**这是唯一真相源**。转换脚本放 `tool/convert_ebml_schema.dart`，生成的 Dart 表放 `lib/src/formats/matroska_schema.dart`。脚本要能重复运行且输出稳定。
- 必须包含的 master 元素：`Segment` / `SeekHead` / `Info` / `Tracks` / `TrackEntry` / `Video` / `Audio` / `Cluster` / `Tags` 等。
- **必须留手写逃生口**：`SimpleBlock` / `BlockGroup` 的 **4 种 lacing** 载荷不可表驱动 → 结构树里当**不透明叶子**。
- WebM 是 Matroska 的子集，schema 里用 `<extension type="webmproject.org" webm="1"/>` 标注 → 表里保留这层信息（用一个布尔字段或注释说明）。

**叶子提取器**：`duration`（`Info`/`Duration` 以 `TimestampScale` 为单位换算）、`codec`（`TrackEntry`/`CodecID` 的原始字符串，如 `V_MPEG4/ISO/AVC`）、`width`/`height`（`Video`/`PixelWidth`/`PixelHeight`）、`sample_rate`（`Audio`/`SamplingFrequency`）、`channels`（`Audio`/`Channels`）、`bit_depth`（`Audio`/`BitDepth`）、`track_type`（按 `TrackType` 映射 video/audio/subtitle）、`overall_bitrate`（derived）。轨道级字段挂在对应 `TrackEntry` 节点上。

**测试**（`test/formats/matroska_test.dart`）：用 `test/fixtures/mkv_vp9_opus_320x240.normal.mkv`、`mkv_vp9_noaudio_320x240.edge.mkv`、`mkv_vp9_opus_320x240.normal.truncated.mkv`、`webm_vp8_vorbis_320x240.normal.webm`、`webm_vp8_vorbis_320x240.normal.truncated.webm`。

**块覆盖率清单**断言：至少能找到 `Segment`/`Info`/`Tracks`/`TrackEntry`/`Video`/`Audio`（无音轨的样本要能优雅处理）。

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
