# RIFF 家族（WAV / AIFF）：规格表 + 叶子提取器

Status: ready-for-agent
Blocked by: 13

## Question / 任务

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

**约束**：纯 Dart，无新依赖。`flutter analyze` 无 issue。
