# FLAC：规格表 + 叶子提取器

Status: resolved
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

## Answer

已实现并合并进 `integration/media-info-mvp`。公开 API：`flacFormat` / `registerFlacFormat()` / `parseFlac` / `extractFlacFields` / `isFlacFile` / `flacContainerSpec`。

**FLAC 没有可用的块树**：元数据块头是 `1 bit last-metadata-block + 7 bit type + 24 bit length` 的位域，通用引擎表达不了（`HeaderRule` 没有标志位，引擎也总是从偏移 0 开始读子块，会把 `fLaC` 魔数当块头）。所以 `parseFlac` **手写**读块头；块载荷仍然走核心引擎的字段读取器（通过 window + "一个子块、无头"的 spec），位序、大小端、长度前缀都没有重复实现。

**STREAMINFO 的位域**用 `FieldType.bits` + `bitWidth`（sample_rate 20 bit / channels 3 bit / bits_per_sample 5 bit / total_samples 36 bit），大端位序，有手打包字节的测试。**注意规范里存的是"值减 1"**，表里字段名是 `channels_minus_one`/`bits_per_sample_minus_one`，节点上暴露的是 `channels`/`bits_per_sample`（已 +1）。

**整合期我改了一处**：给 `flacFormat` 挂了 `parser: parseFlac`。原先 FLAC 模块自己造了一个 `parseFormatContainer` 做 dispatch——**它零调用者（死代码），而且和核心的 `parseFormat` 重复**，已删除。现在所有格式统一走核心入口。

**其它要点**：

- `duration` 标为 **derived**（FLAC 是 total_samples / sample_rate 算出来的），与词表里写的 `read` 有出入——是有意为之。
- 音频帧**不解析**，在树里没有节点；根节点的 size 覆盖它们。所以"在音频区被截断"的文件不会被标为截断。
- 未知/保留的块类型（7..126、127）→ `type: 'UNKNOWN'`、`isOpaque: true`，不丢弃。
- 截断样本正好切在 8192 字节的 PADDING 块里：STREAMINFO/VORBIS_COMMENT 存活，PADDING 的 size 被裁剪。

**验证**：`flutter analyze` 无 issue；全量测试通过；`dart format` 已应用。
