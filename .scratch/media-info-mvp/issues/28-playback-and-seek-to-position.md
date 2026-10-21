# 后续 effort：播放 + 从解析位置跳到播放位置

Status: ready-for-agent
Blocked by: 24

## Question / 任务

**用户明确要求的能力**（在当前 MVP 完成之后做）：应用要能播放音视频，并且**能跳到当前正在解析/查看的位置**——即在结构树里选中某个块，播放器就seek 到对应的时刻。

> 状态：**排在当前 MVP 之后**。本票在 MVP 全部完成后启动，不阻塞当前实现。
> 但它有前置依赖，必须现在就把钩子留好，否则后面要返工。

## 两条独立的难点

### 一、播放能力本身

「不解码、不播放」是当前 MVP 的既定前提（见规格的 Out of Scope），因为纯 Dart 不解码媒体。要播放就得引入一个播放器：

| 方案 | 代价 | 跨平台 |
|---|---|---|
| `video_player` 包 | 用**系统自带**播放器（Windows: Media Foundation，macOS: AVFoundation/AVKit） | ✅ 不需要打包 FFmpeg，**不破坏"零原生依赖"** |
| `media_kit` / `fplayer` | 打包 libmpv / FFmpeg | ❌ 引入原生依赖，且 macOS 侧无法从 Windows 交叉编译 |

**推荐 `video_player`**：走系统解码器，保留"零原生依赖"的前提。代价是**编解码支持取决于操作系统**——Windows 上 HEVC/AV1 常常缺，macOS 上相对完整。这个取舍要在做之前跟用户确认清楚。

### 二、从"字节位置"跳到"播放位置"（这才是真正的新东西）

用户在结构树里选中一个块 → 我们知道它的 `offset`（字节偏移）→ 但播放器要的是**时间戳**。中间缺一层映射：**字节偏移 ↔ 时间**。

各格式的做法：

- **WAV / AIFF** —— 最简单：`时间 = (偏移 - data 块起点) / 字节率`。纯算术。
- **MP3** —— 帧序号 × 每帧采样数 ÷ 采样率。帧头里有偏移。
- **MP4 / MOV** —— 需要 sample table：`stsz`（每个样本的大小）→ 累加得到样本的字节范围 → 偏移落在哪个样本 → `stts`（样本时长）→ 时间戳。**这些表我们的 MP4 规格表已经在解析了**，所以数据是现成的，缺的只是"偏移 → 样本序号 → 时间"这一步。
- **Matroska** —— Cluster 的 `Timecode`（基准时间）+ 块内相对时间。
- **FLAC** —— 帧序号 → 采样数 → 时间；或用 SeekTable。

**结论：这不是"加个播放器"的活，还需要一个新的核心能力——「位置索引」**（byte offset ↔ timestamp 双向映射）。

## 现在就要留的钩子（MVP 阶段必须做）

1. **节点模型里保留 `offset` 与 `size`** —— 已经有了（`ContainerNode`），不要在重构里丢掉。字节偏移是定位的锚点。
2. **解析器要能拿到 sample table 的原始数据** —— MP4 的 `stsz`/`stts`/`stsc`、Matroska 的 Cluster Timecode、FLAC 的 SeekTable 都要**留在结构树里可访问**（现在它们是普通节点，够用），不要在提取器里消化掉后丢弃。
3. **结构树的选中要能向上冒泡到"文档级"** —— 播放器要拿到的是「哪个块 + 它的偏移」，不是「哪个 widget」。
4. **规格里的坐标约定要写清楚**：所有时间都用**秒**（`double`），不用 tick/帧号；字节偏移一律用**文件绝对偏移**。

## 启动这张票前要跟用户确认的

- 用系统解码器（`video_player`，零原生依赖，但 HEVC 支持看 OS）还是打包 FFmpeg（格式覆盖全，但要放弃"零原生依赖"，且 macOS 必须有 Mac 构建机）？
- 播放是**内嵌**在应用里（播放器 widget 嵌在 hex 面板旁边），还是**外部打开**（用系统默认播放器打开该文件）？内嵌体验好但复杂度高一个量级。
- 音频与视频要不要都支持？还是先只做音频？

## 已经查清的事实（省掉后面的调研）

详见 [调研 04 — 预编译 FFmpeg](../../docs/research/04-prebuilt-ffmpeg.md)。要点：

- **"macOS 必须有 Mac 构建机"这个约束被解掉了**——预编译二进制两个平台都有。CI 在 Windows 上下载 macOS 的 `.dylib` 一起打包即可。
- **Windows**：BtbN 每日构建（GPL 与 LGPL 都有，shared 变体 78 MB），或 gyan.dev（essentials 34 MB）。
- **macOS**：Martin Riedl 的构建服务器（amd64 + arm64，9.0，带 SHA256），或 evermeet.cx（**仅 x86_64，官方说不做 arm64**）。
- **BtbN 没有 macOS 构建**——用 GitHub API 核过 51 个 asset，只有 win*/linux*。
- **许可有个不对称**：Windows 侧现成的 LGPL 和 GPL 都有；**macOS 侧现成的都是 GPLv3**。我们的仓库是公开开源的，**整个应用走 GPL 是最省事的路线**；要保持宽松许可，macOS 侧得自己编译（要 Mac）或另找 LGPL 源。
- **体积**：当前 Windows zip 是 11 MB，带 FFmpeg 会涨到 80–190 MB。可以只带 shared 库、或把 FFmpeg 做成**按需下载**。

## 产出

一份针对"播放 + 位置索引"的规格，以及实现票。**不在本次 effort 内实现。**
