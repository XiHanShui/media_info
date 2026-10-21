# 调研 04 — 预编译 FFmpeg（Windows + macOS 双平台）

> 对应票：`.scratch/media-info-mvp/issues/28-playback-and-seek-to-position.md`
> 目的：验证"引入 FFmpeg 做播放"这条路在**两个平台上都有现成二进制**——因为
> `flutter build macos` 在非 macOS 主机上会直接报错退出，自己编译 macOS 版必须有一台 Mac。

## 结论摘要

**有现成的预编译二进制，而且 macOS 也有 arm64 版本。** 这直接解掉了"必须要有 Mac 构建机"这个硬约束：
CI 在 Windows 上下载 macOS 的预编译 `.dylib` 一起打包即可，不需要 Mac。

但有一个**许可上的不对称**需要决策：Windows 侧现成有 GPL 和 LGPL 两套，**macOS 侧现成的都是 GPLv3**。

| 平台 | 提供方 | 架构 | 许可 | 版本 | 备注 |
|---|---|---|---|---|---|
| Windows x64/arm64 | [BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds/releases) | x86_64, arm64 | **GPL 与 LGPL 都有** | master / 9.0 / 8.1 | 每日自动构建，每版带 `checksums.sha256` |
| Windows | [gyan.dev](https://www.gyan.dev/ffmpeg/builds/) | x86_64 | GPLv3 | 9.0.2 / 8.1.2 / git master | 有 `essentials`(34MB) / `full` / `full-shared` 三个变体；也镜像在 [GyanD/codexffmpeg](https://github.com/GyanD/codexffmpeg) |
| macOS | [Martin Riedl 的 FFmpeg Build Server](https://ffmpeg.martin-riedl.de/) | **amd64 与 arm64 都有** | GPLv3 | 9.0（带 .sha256 旁挂文件） | 稳定版，非滚动 |
| macOS | [evermeet.cx](https://evermeet.cx/ffmpeg/) | **仅 x86_64** | GPL（`--enable-gpl`） | 快照 / release | 官方说明"不打算提供 Apple Silicon 原生二进制"；需 macOS 10.13+ |
| macOS | OSXExperts | amd64 | — | 8.0 / 7.x | 老版本 |

**BtbN 没有 macOS 构建**——这一点用 GitHub API 查过 `latest` release 的全部 51 个 asset，只有 `win64*` / `winarm64*` / `linux64*` / `linuxarm64*`，没有任何 macOS 资产。想当然会踩坑。

macOS 的预编译来源与下载 URL 可以直接参考 [mrkbac/portable-ffmpeg](https://github.com/mrkbac/portable-ffmpeg) 的映射表（它把各平台的来源、版本、许可、SHA256 都列清楚了）：

- macOS amd64 9.0：`https://ffmpeg.martin-riedl.de/download/macos/amd64/1785871427_9.0/ffmpeg.zip`
- macOS arm64 9.0：`https://ffmpeg.martin-riedl.de/download/macos/arm64/1785863997_9.0/ffmpeg.zip`

（该服务器在调研时对本机返回 521，实际可用性要在用的时候再确认。）

## 体积

BtbN 各变体的 zip 大小（master 版）：

| 变体 | Windows x64 | Windows arm64 |
|---|---|---|
| GPL static | 191.2 MB | 135.1 MB |
| LGPL static | 169.7 MB | 118.0 MB |
| GPL shared | 87.2 MB | 62.0 MB |
| **LGPL shared** | **78.3 MB** | **55.5 MB** |

gyan.dev 的 `essentials` 变体只有 34 MB（.7z）。

对比：当前应用的 Windows zip 是 **11 MB**。引入 FFmpeg 会让包体涨 3–8 倍。

**减体积的手段**：

1. 用 **shared** 变体，只带真正需要的 dll（播放只需要 `libavformat` + `libavcodec` + `libavutil` + `libswresample`），不带 `ffmpeg.exe`/`ffplay.exe` 这些命令行工具。
2. 自己用 `--disable-everything --enable-demuxer=... --enable-decoder=...` 裁剪——但这就**回到自己编译**，macOS 侧又要 Mac。
3. **把 FFmpeg 做成可选下载**：主包保持小体积，首次使用播放功能时按需下载对应平台的二进制。这是很多工具的做法。

## 许可决策（必须做，不能拖）

FFmpeg 默认 **LGPL v2.1+**，`--enable-gpl` 或链接了 libx264/x265 等 GPL 库时变成 **GPL v2+**。

- **GPL 路线**：现成的预编译包几乎全是 GPL。**静态链接 GPL 的 FFmpeg 会让我们的应用整体变成 GPL。**
  → 我们的仓库是**公开开源**的（`XiHanShui/media_info`），把应用本身也按 GPL 发布是可以接受的。**这是最省事的路线。**
- **LGPL 路线**：动态链接 + 随包附带 LGPL 副本与声明 + 用户可替换库（§6(b)），我们自己的代码可以保持别的许可。
  → 但 **macOS 侧找不到现成的 LGPL 预编译包**（Martin Riedl 与 evermeet 都是 GPL）。要走 LGPL，macOS 侧要么自己编译（要 Mac），要么找一个 LGPL 的 macOS 构建（未验证是否存在）。
  → **Windows 侧没这个问题**：BtbN 有 `win64-lgpl-shared`。

**待用户拍板**：是"整个应用走 GPL"（用现成的包，两个平台都有），还是"应用保持宽松许可"（Windows 用 LGPL、macOS 自己编译或另找 LGPL 源——后者需要 Mac 构建机，与我们"Windows 优先、macOS 靠 CI"的现状冲突）。

## 与 `video_player` 的对比

| | 预编译 FFmpeg | `video_player`（系统解码器） |
|---|---|---|
| 原生依赖 | 要（FFI 绑定） | **不要** |
| macOS 交叉编译 | ✅ 预编译二进制解决 | ✅ 无所谓 |
| 编解码覆盖 | **完整**（含 HEVC/AV1/ProRes……） | **看操作系统**：Windows 上 HEVC/AV1 常缺 |
| 体积 | +80–190 MB | 0 |
| 许可 | GPL/LGPL 要决策 | 宽松 |
| 能否"跳到解析位置" | 能（自己控制解码与 seek） | 能，但只能按时间 seek |

**注意**：即使选了 `video_player`，"从解析位置跳到播放位置"所需的**位置索引**（字节偏移 ↔ 时间戳）仍然要自己做——那是本项目的核心能力，与用不用 FFmpeg 无关。

## 对本 effort 的影响

**没有影响当前 MVP**——这张票排在 MVP 完成之后。但两件事现在就要留意：

1. **别把架构写死成"不用 FFmpeg"**。核心层是纯 Dart 的，格式解析也不碰 FFmpeg，所以**将来加播放不会推翻现有设计**——这正是当初坚持"纯 Dart 解析器"的价值。
2. **位置索引现在就得留钩子**（见票 28 的"现在就要留的钩子"一节）。

## 引用来源

- BtbN/FFmpeg-Builds releases（asset 列表经 GitHub API 核对）— <https://github.com/BtbN/FFmpeg-Builds/releases>
- gyan.dev FFmpeg Builds — <https://www.gyan.dev/ffmpeg/builds/>
- evermeet.cx macOS 静态构建 — <https://evermeet.cx/ffmpeg/>
- Martin Riedl FFmpeg Build Server — <https://ffmpeg.martin-riedl.de/>
- mrkbac/portable-ffmpeg（各平台来源与 URL 映射）— <https://github.com/mrkbac/portable-ffmpeg>
- FFmpeg 官方下载页（FFmpeg 只提供源码，编译版由第三方提供）— <https://ffmpeg.org/download.html>
- FFmpeg COPYING.LGPLv2.1（§6 的链接与源码义务）— <https://github.com/FFmpeg/FFmpeg/blob/master/COPYING.LGPLv2.1>
- FFmpeg 官方许可说明（默认 LGPL，--enable-gpl 变 GPL）— <https://github.com/FFmpeg/FFmpeg/blob/master/LICENSE.md>
