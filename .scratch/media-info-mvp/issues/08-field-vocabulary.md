# 统一语义字段词表

Type: grilling
Status: resolved
Blocked by: 01

## Question

跨格式统一的**字段名清单**是什么？以及同一个概念在不同格式里怎么归一？

要定下来的：

- **通用字段**（多格式共有）：时长、文件大小、codec 标识、轨道数……逐个列出。
- **轨道级字段**：分辨率、帧率、采样率、位深、声道数、推算的平均码率。
- **格式特有字段**：只在某类格式里有意义的（FLAC 的 bits-per-sample 与 MD5、WAV 的每个 chunk 布局、MP4 的 track handler）——放不放进统一词表，还是各格式自己带？
- **归一难题**：同一个概念在不同格式下取自不同位置——采样率在 WAV 来自 `fmt ` chunk、在 FLAC 来自 STREAMINFO、在 MP4 来自 `esds`。这些差异在数据模型里怎么表达（统一字段名 + 各自的原始来源？还是保留各格式原生的字段名，只做显示层归一？）？
- **英文技术名 + 中文显示名**的对照——英文名是代码里的标识符，必须能与规范对照；中文名是界面显示。

**产出**：一张字段词表（英文技术名 / 中文显示名 / 适用格式 / 取值来源 / 是否推算）。

**为什么阻塞于[统一节点模型与双视图的数据来源](01-unified-node-model.md)**：字段挂在节点的哪一级（文件级 / 轨道级 / 块级）由节点模型决定。

**注意**：本票**不覆盖**"标签/元数据"（那是[标签 / 元数据与语义字段的边界](09-tag-vs-field-boundary.md)），也不做编码参数级字段。

## Answer

**归一方式**：统一词表只管**键名**（英文技术名 = 代码标识符 = 与规范逐字对照的术语）；**各格式原生的字段名不丢**——每个语义字段额外携带 `source`，记着它是从哪个块的哪个字段读出来的（例如 `sample_rate` 的 source 是 `WAV fmt ` / `FLAC STREAMINFO` / `MP4 esds`）。

### 文件级（所有格式共有）

| key | 中文 | 单位 | origin | 备注 |
|---|---|---|---|---|
| `file_name` | 文件名 | — | read | |
| `file_size` | 文件大小 | byte | read | |
| `container_format` | 容器格式 | — | read | 如 `WAV` / `MP4` / `Matroska` |
| `duration` | 时长 | s | read | 推不出来时为空 |
| `overall_bitrate` | 平均码率 | bit/s | derived | 文件大小 ÷ 时长 |

### 轨道级

| key | 中文 | 单位 | origin | 备注 |
|---|---|---|---|---|
| `track_index` | 轨道序号 | — | read | |
| `track_type` | 轨道类型 | — | read | `video` / `audio` / `subtitle` |
| `codec` | 编码标识 | — | read | 原始 fourcc / codec id，**不翻译** |
| `width` | 宽度 | px | read | 视频 |
| `height` | 高度 | px | read | 视频 |
| `frame_rate` | 帧率 | fps | read | 视频 |
| `sample_rate` | 采样率 | Hz | read | 音频 |
| `bit_depth` | 位深 | bit | read | 音频 |
| `channels` | 声道数 | — | read | 音频 |
| `language` | 语言 | — | read | 有则显示 |

### 格式特有（不进统一词表，挂在各格式自己的节点上）

FLAC 的 `total_samples`、`md5`；MP3 的 `mpeg_version`、`layer`、`bitrate_mode`；MP4 的 `timescale`、`handler_type`、`brand`；Matroska 的 `timestamp_scale`、`duration`（以 TimestampScale 为单位）。

### 规则

- **英文技术名永远不翻译**（对应 user story 47）；中文只出现在界面显示名。
- 同一个 key 在不同格式下的值必须**同单位同含义**，否则不进统一词表，改用格式特有字段。
- `origin` 区分「文件里直接写的」与「我们推算的」，界面必须标出（对应 user story 15）。
- 轨道级字段挂在**对应轨道的节点**上，文件级字段挂在**根节点**上。

