# FLAC：规格表 + 叶子提取器

Status: ready-for-agent
Blocked by: 13

## Question / 任务

**模块导出约定**：创建 `lib/src/formats/flac.dart`，导出 `FormatSpec get flacFormat`、`void registerFlac()`。**不要在 import 时做注册副作用**，也不要创建 `all_formats.dart`（那是实现票 20 的统一入口）。

实现 **FLAC** 的规格表与语义字段提取。

**必读**：`docs/design/core-api.md`、[调研 02](../../docs/research/02-declarative-parsers.md) §1.4 与 §4（FLAC 不规则点）。

**规格表**（`lib/src/formats/flac.dart`）：

- 文件头：`fLaC` 魔数，随后是元数据块序列。
- 块头：**1 bit `last-metadata-block` + 7 bit 类型 + 24 bit 长度**（大端）。
- 7 种块：`STREAMINFO`(0) / `PADDING`(1) / `APPLICATION`(2) / `SEEKTABLE`(3) / `VORBIS_COMMENT`(4) / `CUESHEET`(5) / `PICTURE`(6)。
- `STREAMINFO` 是**位域**：`min_block_size` u16 / `max_block_size` u16 / `min_frame_size` u24 / `max_frame_size` u24 / `sample_rate` **20 bit** / `channels` **3 bit** / `bits_per_sample` **5 bit** / `total_samples` **36 bit** / `md5` 16 byte。
- `VORBIS_COMMENT` 的长度字段是**小端**（FLAC 唯一的字节序例外）——`endian: Endian.little`。
- `PADDING` / `APPLICATION` 的载荷是纯字节（长度由块头决定）→ 不透明叶子。

**叶子提取器**：`sample_rate`、`bit_depth`、`channels`、`duration`（`total_samples / sample_rate`）、`codec`（`FLAC`）、`overall_bitrate`（derived）。格式特有字段 `total_samples`、`md5` 挂在 `STREAMINFO` 节点上（不进统一词表）。

**测试**（`test/formats/flac_test.dart`）：用 `test/fixtures/flac_s16_44100_stereo.normal.flac`、`flac_s24_96000_mono.edge.flac`、`flac_s16_44100_stereo.normal.truncated.flac`。

**块覆盖率清单**断言：至少能找到 `STREAMINFO`（块类型名用规范名）与 `VORBIS_COMMENT`。

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
