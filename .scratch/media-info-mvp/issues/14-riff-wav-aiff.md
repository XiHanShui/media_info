# RIFF 家族（WAV / AIFF）：规格表 + 叶子提取器

Status: ready-for-agent
Blocked by: 13

## Question / 任务

**模块导出约定**：创建 `lib/src/formats/riff.dart`，导出 `FormatSpec get wavFormat`、`FormatSpec get aiffFormat`、`void registerWav()`、`void registerAiff()`。**不要在 import 时做注册副作用**，也不要创建 `all_formats.dart`（那是实现票 20 的统一入口）。

用核心引擎实现 **RIFF 家族**（WAV、AIFF）的规格表与语义字段提取。

**必读**：`docs/design/core-api.md`、[统一语义字段词表](08-field-vocabulary.md)（字段键名与中文显示名以它为准）。

**规格表**（`lib/src/formats/riff.dart`）：

- `RIFF` / `LIST` 是容器型（带 form type），其余 chunk 按表处理，未知 chunk 走"不透明叶子"。
- WAV：块头 = `id`(4) + `size`(LE32)，**奇数长度补 1 字节**（`padTo = 2`）。`fmt ` 载荷是 tagged union（`wFormatTag` 决定 `WAVEFORMATEX` / `WAVEFORMATEXTENSIBLE`），末尾有 `cbSize` 自描述扩展——**这一处需要手写逃生口**（表只能表达"定长头 + N 字节扩展"）。
- AIFF：`COMM` 块、`SSND` 块、Big-Endian 数值。AIFF 的 `COMM` 载荷是定长字段（`numChannels` u16 / `numSampleFrames` u32 / `sampleSize` u16 / `sampleRate` 80-bit extended）。

**叶子提取器**：产出统一词表里的字段——
- WAV：`sample_rate`、`bit_depth`、`channels`、`duration`、`codec`（`wFormatTag`）、`overall_bitrate`（derived）
- AIFF：`sample_rate`、`bit_depth`、`channels`、`duration`、`codec`

**测试**（`test/formats/riff_test.dart`）：用 `test/fixtures/` 里的
`wav_pcm_s16le_44100_stereo.normal.wav`、`wav_pcm_u8_8000_mono.edge.wav`、`wav_pcm_s24le_48000_stereo.edge.wav`、`wav_pcm_s16le_44100_stereo.normal.truncated.wav`（截断 → 断言降级 + 有错误信息）、`wav_pcm_s16le_44100_stereo.normal.liesize.wav`（长度撒谎 → 断言不越界不崩）、`aiff_pcm_s16be_48000_mono.normal.aiff`、`aiff_pcm_s24be_44100_stereo.edge.aiff`。

另加**块覆盖率清单**断言：WAV 至少能找到 `RIFF`/`fmt `/`data`；AIFF 至少能找到 `FORM`/`COMM`/`SSND`。

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
