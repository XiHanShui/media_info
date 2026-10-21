# ISO BMFF（MP4 / MOV）：规格表 + 叶子提取器

Status: ready-for-agent
Blocked by: 13

## Question / 任务

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
