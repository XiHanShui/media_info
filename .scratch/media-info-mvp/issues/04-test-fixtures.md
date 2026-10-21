# 测试素材获取与归档

Type: task
Status: resolved
Blocked by:

## Question

各格式的样本文件从哪来、放在哪、怎么进仓库？这是**所有解析器测试的前置**——没有素材，[统一节点模型与双视图的数据来源](01-unified-node-model.md) 与[容器格式能否用声明式规格表描述](02-declarative-parsers.md) 的结论无法验证，所以它必须排在实现之前完成。

本票是**动手做事**，不是做决定：

- **素材清单**：每个目标格式（WAV / AIFF / FLAC / MP3 / MP4 / MOV / MKV / WebM）需要哪些样本？建议每种至少三类——
  - 正常样本（最常见的参数组合）
  - 边界样本（最小尺寸、罕见参数、非典型但合法的组合）
  - 损坏样本（截断、长度字段撒谎、未知块、CRC 失败）
- **来源**：自己用 ffmpeg / 脚本生成？还是取公开样本库？哪些能进仓库、哪些需要脚本现生成？
- **存放位置与体积**：放 `test/fixtures/`？大文件是否入 git？要不要 Git LFS？还是提交生成脚本 + 小体积黄金样本（golden files）、大文件现场生成？
- **命名规范**：怎么从文件名看出格式、类别、参数（例如 `wav_pcm_s16le_44100_stereo.normal.wav`）？
- **版权**：公开样本库里的文件能否再分发？

**产出**：素材清单 + 落地方案（目录结构、生成脚本或取样来源、命名规范）。若方案包含提交脚本，脚本本身一并落地。

**注意**：这票做完之前不要开始写解析器——否则验证会退化成"拿手头随便一个文件试"。

## Answer

素材已落地：`test/fixtures/`，**24 个文件，合计约 550 KB**，随仓库提交。生成脚本 `tool/gen_fixtures.dart`（纯 Dart 标准库，无新依赖），`dart run tool/gen_fixtures.dart` 可完整重现。

**来源**：全部用本机 ffmpeg（`G:\WS\ffmpeg\ffmpeg\bin\ffmpeg.exe`，full build）**本地确定性生成**，不下载任何外部内容 —— 因此没有版权问题，也不需要 LFS 或素材站。

**存放位置**：`test/fixtures/`，扁平目录，格式与类别由文件名承载。550 KB 足够小，直接进 git；Git LFS 不需要。

**命名规范**：`<格式>_<参数>.<类别>.<扩展名>`，例如 `wav_pcm_s16le_44100_stereo.normal.wav`。类别四取一：`normal` / `edge` / `truncated` / `liesize`。

**素材清单**（24 个）：

- **正常（8）**——每种目标格式各一个最常见参数组合：wav s16le/44.1k/立体声、aiff s16be/48k/单声道、flac s16/44.1k、mp3 CBR 128k、mp4 h264+aac 320x240、mov mpeg4+aac、mkv vp9+opus、webm vp8+vorbis。
- **边界（7）**——8bit/8kHz 单声道 WAV、24bit WAV、24bit AIFF、24bit/96kHz FLAC、VBR MP3、MP4 无音轨、MKV 无音轨。
- **损坏（9）**——8 个正常样本各自截断到 60%（文件声明的长度大于实际内容），外加 1 个 WAV 长度字段撒谎（RIFF 长度改成 `0xFFFFFFFF`、data 块长度改成 `0xFFFFFF00`）。

**已知限制**：

- 素材由 ffmpeg 生成，**只覆盖 ffmpeg 会写出的那种布局**。真实世界里千奇百怪的文件（多个 `mdat` 的 MP4、`moov` 位于文件尾部的 MP4、fMP4 分片、非标准 mux 的 MKV）造不出来，需要另外补。
- 截断样本只覆盖"文件被砍断"这一种损坏形态，没有覆盖其它损坏方式。

**对下游票的影响**：

- 两条测试接缝现在有语料了，可以开工。
- [以 MediaTrace 作为结构树的离线校验基准](12-mediatrace-offline-oracle.md) 解锁——它阻塞于本票。

