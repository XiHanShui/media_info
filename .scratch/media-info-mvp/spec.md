# media_info MVP — 产品规格

Status: ready-for-agent
Map: [media_info MVP 规格](map.md)

> 本规格由 /wayfinder 的 charting + 两轮 grilling 合成。**未决事项**一节显式列出仍开放的决策票——
> 涉及这些区域的实现可以先做不依赖它们的部分。

## Problem Statement

我经常需要弄清一个音视频文件到底是什么。目前的手段都有问题：

- 系统自带的属性面板只给几个字段（时长、尺寸），看不到容器的内部结构。
- MediaInfo 虽然能读几十种格式，但它的 "Details" 是一段文本化的树，我没法在某个块上停下来、看清它占了文件的哪个偏移、多长、原始字节长什么样。
- 想看一个 WAV 的 16bit 头信息、或一个 MP4 里每个 box 的边界，只能上命令行工具手动 hexdump。

我想要一个 Windows 和 macOS 上都能用的桌面工具：丢一个文件进去，同时看到**这个文件是什么**（时长、编码、采样率、位深……）和**这个文件由什么构成**（可展开的块，每块带偏移量与长度，能下钻到原始 hex）。而且它要覆盖音频和视频两类格式，不只是某一个。

## Solution

一个 Flutter 桌面应用。打开文件后，界面并排呈现两棵视图：

- **语义字段视图**——按文件级与轨道级分组的解码值：时长、codec 标识、分辨率、帧率、采样率、位深、声道数、推算的平均码率。
- **结构树视图**——容器内部逐层可展开的**块**树。每个块显示名称、类型、在文件中的偏移量与长度。选中任意一个块，右侧显示它的原始 hex 与 ASCII。

同一个文件可以开多个标签页并排比较。字段值可右键复制，整个结果可导出为 JSON。

MVP 覆盖的格式：WAV、AIFF、FLAC、MP3（音频方向）与 MP4/MOV、MKV/WebM（视频方向）。解析全部用纯 Dart 手写实现，不引入任何原生依赖。

**参考与借鉴**：功能定位参考雷霄骅的 **VideoEye**（<https://github.com/leixiaohua1020/VideoEye>，开源实时码流分析软件，C++/MFC + FFmpeg + MediaInfo.dll）。我们借鉴它两点：① **图形化呈现分析结果**——结构树上显示每个块占文件大小的比例，一眼看出哪块最占地方；② **逐层下钻**——从容器结构一路点到具体块。我们**不**做它的实时/网络流输入（HTTP/RTMP/RTSP）、**不**做解码与播放（见后续 effort）、**不**做 TI/SI 画质指标与人脸检测（都要解码像素，超出本工具定位）。

**格式一律由文件内容判定，扩展名只作提示。** 一个叫 `movie.mp4` 的文件完全可能是 Matroska、甚至就是 WAV。应用按内容嗅探与解析；当扩展名与实际格式不符时，界面明确提示（「扩展名 `.wav` 与实际格式 `MP4` 不符」）——是提示不是报错，解析照实际内容走。

## 未决事项

**（无——12 张决策票已全部解完，结论已回写进本规格。）**

若后续出现新的待决项（例如构建期发现某个格式的表表达不出来），按 wayfinder 的方式在地图上开新票，并在此处登记。

**决策票与结论的索引**见 [地图的 Decisions so far](map.md)。

**实现票**（13–27 号）与实现层契约见 `docs/design/core-api.md`。

## User Stories

### 打开与浏览文件

1. As a 音视频工程师, I want 把文件拖进窗口就打开, so that 不用先开一个文件选择对话框。
2. As a 音视频工程师, I want 通过文件选择器打开文件, so that 我可以浏览目录而不是记得路径。
3. As a 音视频工程师, I want 同时打开多个文件各占一个标签页, so that 我能对比两个不同编码的版本。
4. As a 音视频工程师, I want 在标签页之间快速切换, so that 我不用关掉重开。
5. As a 音视频工程师, I want 关闭一个标签页后其余不受影响, so that 我不会丢掉正在看的内容。
6. As a 音视频工程师, I want 界面告诉我当前打开的是哪个文件, so that 多个标签页时不会搞混。
7. As a 音视频工程师, I want 打开一个很大的文件时界面不要卡死, so that 我能继续做别的事。

### 语义字段

8. As a 音视频工程师, I want 看到这个文件的时长, so that 我知道它大概多长。
9. As a 音视频工程师, I want 看到文件大小和推算的平均码率, so that 我能判断它的质量档次。
10. As a 音视频工程师, I want 看到它有几条轨道, so that 我知道里面有几个视频/音频/字幕流。
11. As a 音视频工程师, I want 看到每条轨道的 codec 标识, so that 我知道它用的什么编码。
12. As a 音视频工程师, I want 看到视频轨道的分辨率和帧率, so that 我能确认它符不符合我的规格。
13. As a 音视频工程师, I want 看到音频轨道的采样率、位深和声道数, so that 我能确认它是不是我需要的 16bit 立体声。
14. As a 音视频工程师, I want 音频和视频的字段分组显示而不是混在一起, so that 我能一眼分清。
15. As a 音视频工程师, I want 知道某个字段是文件里直接写的还是我算出来的, so that 我不会把推算值当成原始值引用。
16. As a 音视频工程师, I want 右键复制一个字段的值, so that 我能直接粘到文档里。

### 结构树

17. As a 音视频工程师, I want 看到文件内部的结构树, so that 我能知道它由哪些块组成。
18. As a 音视频工程师, I want 每个块显示它在文件中的偏移量和长度, so that 我能定位它。
19. As a 音视频工程师, I want 能逐层展开嵌套的块, so that 我能深入到具体的样本表或编解码配置。
20. As a 音视频工程师, I want 看到块的原始类型标识（英文规范名）, so that 我能对照规范逐字查证。
21. As a 音视频工程师, I want 折叠某个块时它的子块一起收起来, so that 树不会乱成一团。
22. As a 音视频工程师, I want 遇到我不认识的块时它仍然显示出来, so that 我不会以为文件里没有这部分内容。
23. As a 音视频工程师, I want 看到 moov 这类包含大量子块的容器时树仍然能顺畅滚动, so that 几千个子条目不会把界面拖垮。
24. As a 音视频工程师, I want 展开一个块时才去读它的内容, so that 大文件也能秒开。

### 原始字节

25. As a 音视频工程师, I want 选中一个块时看到它的原始 hex, so that 我能确认解析器读对了没有。
26. As a 音视频工程师, I want 在 hex 旁边看到 ASCII 侧栏, so that 我能一眼认出里面的字符串。
27. As a 音视频工程师, I want 能看到当前高亮的是哪几个字节, so that 我能把 hex 和字段值对应起来。
28. As a 音视频工程师, I want hex 视图能独立滚动, so that 我能对照看头尾。

### 格式覆盖

29. As a 音视频工程师, I want 读 WAV 文件的 RIFF chunk 布局, so that 我能看到 fmt 和 data 各自多大。
30. As a 音视频工程师, I want 从 WAV 读到 16bit、采样率、声道数, so that 我能确认它是不是目标格式。
31. As a 音视频工程师, I want 读 AIFF 的 FORM chunk 结构, so that 我能对比它和 WAV 的异同。
32. As a 音视频工程师, I want 读 FLAC 的 metadata block 和 STREAMINFO, so that 我能看到位深、采样率、总采样数。
33. As a 音视频工程师, I want 读 MP3 的帧头, so that 我能看出版本、码率、采样率。
34. As a 音视频工程师, I want 读 MP4 的完整 box 树（ftyp、moov、trak、mdia、stsd……）, so that 我能看到每个 box 的边界。
35. As a 音视频工程师, I want 从 MP4 读到时长、分辨率、帧率、codec 标识, so that 我能快速核对一个视频。
36. As a 音视频工程师, I want 读 MOV, so that 我处理 QuickTime 素材时也有结构可看。
37. As a 音视频工程师, I want 读 MKV/WebM 的 EBML 元素树, so that 我能看到 Segment、Info、Tracks 的结构。
38. As a 音视频工程师, I want 从 MKV 读到时长、轨道信息、视频尺寸, so that 我能核对它。
39. As a 音视频工程师, I want 遇到还没支持的格式时收到清楚的提示而不是崩溃, so that 我知道该换工具还是该提需求。
40. As a 音视频工程师, I want 一个文件的所有轨道的字段都列出来, so that 多音轨文件不会漏看。

### 导出与协作

41. As a 音视频工程师, I want 把整个分析结果导出成 JSON, so that 我能用脚本二次处理。
42. As a 音视频工程师, I want 导出的 JSON 同时包含语义字段和结构树, so that 我不用分别导出两份。
43. As a 音视频工程师, I want 导出的字段名用英文技术名, so that 它和格式规范对得上。

### 平台与体验

44. As a 音视频工程师, I want 在 Windows 上直接双击一个 exe 就用起来, so that 我不用装一堆东西。
45. As a 音视频工程师, I want 在 macOS 上也有同样功能的版本, so that 我换机器不用换工具。
46. As a 音视频工程师, I want 界面是中文的, so that 我不用来回对照英文术语。
47. As a 音视频工程师, I want 界面里的字段名和块名保持英文原词, so that 我能直接拿去查 ISO 或 Matroska 规范。
48. As a 音视频工程师, I want 遇到损坏或截断的文件时看到明确的错误说明, so that 我知道是文件的问题而不是工具的 bug。
49. As a 音视频工程师, I want 解析失败时仍然能看到已经读到的部分结构, so that 我能定位文件在哪断的。
50. As a 音视频工程师, I want 工具本身不联网、不上传文件, so that 我的素材不会外泄。
51. As a 开发者, I want 项目的解析器易于新增格式, so that 我以后加 AVI/ASF/MPEG-TS 不用重构架构。
52. As a 开发者, I want 每个格式的解析都有可复现的样本与断言, so that 我改了解析逻辑能立刻知道有没有破坏别的格式。
53. As a 音视频工程师, I want 应用按文件内容判定格式而不是信扩展名, so that 一个后缀写错但内容是 MP4 的文件也能正确解析。
54. As a 音视频工程师, I want 在扩展名与实际格式不一致时看到明确提示, so that 我知道这个文件的真实身份、也不会误以为程序认错了。
55. As a 音视频工程师, I want 在结构树里看到每个块占文件大小的比例, so that 我能一眼看出哪块最占地方、哪块只是元数据。

## Implementation Decisions

**平台与技术栈**

- Flutter 桌面应用，目标是 Windows 与 macOS。Windows 优先推进，macOS 随后由用户在自己的 Mac 上验证。
- Dart SDK 约束不低于 3.10（代码使用 Dart 3 的点简写语法）；Flutter 版本钉在 3.41.6 stable，不使用 `latest`。
- 界面文案中文；代码内部标识符、字段名、块类型名一律英文，以便与格式规范逐字对照。

**解析层**

- 每种格式一个解析器，纯 Dart 手写，不引入 C/C++、FFmpeg 或 MediaInfoLib。**理由**：我们要的是**原始结构 + 结构化数据**；现成方案给的都是**解读 + 文本 blob**——MediaInfo 的 MediaTrace 虽是带 offset 与 size 的真块树，但那是它自己的语义解读树（块名被换成 `Element_Name("File Type")` 之类的标签、未知块被折叠、大块只给 "(N bytes)" 摘要、**无 hex**），而且只能拿到一整块预渲染的 XML 文本，真正的树对象在 C++ 内部不导出；FFmpeg 则根本没有块树（`av_dump_format` 只打印元数据，`AVIO_FLAG_TRACE` 已从 master 移除）。引入任一原生库还会立刻加上"必须有 macOS 构建机"的硬约束——`flutter build macos` 在非 macOS 主机上直接报错退出。详见 [调研结论](../../docs/research/03-mediainfo-ffprobe-depth.md)。
- 解析层分**三层**，不要在"N 个手写解析器"和"N 张表 + 1 个引擎"之间二选一：
  1. **规格表**（声明式数据）——每种格式一张表：MP4 的 box 表、Matroska 的 element 表、RIFF 的 chunk 表、FLAC 的 block 表。Matroska 的表**已经由规范以机器可读形式发布**（`ebml_matroska.xml`，262 个元素 / 49 个 master 元素），转换为 Dart 表是机械工作，官方 XML 是唯一真相源。
  2. **通用容器引擎**（代码，只写一次）——读头 → 查表 → 走字段 → 递归 → 产出统一节点。
  3. **叶子提取器**（少量手写）——从已解析的树里取语义字段，每格式一个，不重复解析字节。
- 这个划分与语义字段的深度约束天然对齐：结构树（偏移/长度/hex）由第 1+2 层产出，语义字段由第 3 层产出；"语义字段只做到轨道级、不做编码参数级"恰好让第 3 层保持很小。
- **通用引擎必须支持的能力**：32/64 位长度 + "size==0 延伸到 EOF"、变长整数（VINT）、unknown size + 基于路径的收尾判定、version 条件字段、24 位 flags、按前一字段决定后续数组宽度、计数前缀数组 / 嵌套记录、长度前缀字节串、**位域（bit-level）字段**、块内字节序切换、动态 type 分派 + 二级表、自描述尾部长度、**"未知即跳过"兜底**。最后一条是刚需——三种格式的规范都要求忽略并跳过未识别的类型，因此引擎永远能产出完整的结构树，即使遇到没见过的扩展。
- **必须留手写逃生口的地方**（不能只靠表）：MP4 的 `stsd` 动态 sample entry（`avcC` 定义在 14496-15 而非 14496-12）、`stz2` 的运行期定宽数组、`colr` 按 tag 分派的变长载荷；EBML 的 Block Lacing（载荷不可表驱动，结构树里当不透明叶子）；RIFF 的 chunk type 无中心注册表（表只能"通配 + 不透明"）、`fmt ` 是带 `cbSize` 扩展的 tagged union；FLAC 的位域载荷与 Vorbis comment 的小端例外。
- 各容器的块头规则：ISO BMFF 是 8/16 字节 box 头（`size == 1` 走 64 位扩展，`size == 0` 到文件尾）、RIFF 是 `id + LE32 size`（奇数长度补 1 字节）、EBML 是 element id + VINT size（含未知长度哨兵）、FLAC 是元数据块（last-metadata-block 标志 + 24 位长度）、MP3 是帧序列（**这一档没有真正的块树**，按帧列表呈现）。原始 hex 由 Dart 侧按 offset/size 自行从文件读取。
- **注册表登记的是规格表 + 可选的叶子提取器**，不是解析器对象——第三方加一个新容器 = 写一张表。扩展点的形状不变，粒度变细。
- **不引入的库**：`binstruct`（只有 8/16 位整数 + float32，补齐所需能力等于重写，且无维护者）、Kaitai `.ksy`（pub.dev 上没有 Dart 运行时）、`mediaindex_dart`（SDK 约束 `<3.0.0`，本机 resolve 不下来）、直接依赖 `ebml` 包（形态对但 2023-09 后未更新、只内置 EBML Header 表——但它的 `SchemaElement` 字段设计值得抄）。Dart 生态没有可用的通用声明式二进制解析库，需自建 DSL + 引擎（约 300–500 行）。
- **先做纵切验证**：用最小表集实现 MP4 的 `moov → trak → mdia → minf → stbl → stsd`，确认 version 条件字段 + 动态 type 分派能在引擎里表达，再推广到其它三种格式。
- 详细依据见 [调研 02](../../docs/research/02-declarative-parsers.md) 与 [调研 03](../../docs/research/03-mediainfo-ffprobe-depth.md)。
- **节点模型**：一棵节点树，两个视图都是它的投影。节点持有 `type`/`offset`/`size`/`dataOffset`/`dataSize`/`isOpaque`/`children`/`fields`；语义字段持有 `key`（英文技术名）/ `label`（中文显示名）/ `value`/`unit`/`origin`（read 来自文件 / derived 推算）/`scope`（file / track）/`trackIndex`/`source`。节点**不持有字节内容**，只持有 offset 与 size，hex 视图按需从文件读。契约见 `docs/design/core-api.md`。
- **字节访问**：`RandomAccessFile` 随机访问，绝不整体读入内存；偏移与长度一律用 64 位 `int`（支持 >4GB 文件、`largesize`、`co64`）。结构树**惰性展开**——初始只建第一层，子块在用户展开时才解析。
- 未知块与损坏文件必须降级展示，不能让整个解析失败——已读到的部分结构仍然呈现，错误以明确形式给出。读到的字节少于声明长度时立即停止，标记「截断」并给出中文错误说明（"文件在偏移 X 处截断，声明长度还差 N 字节"）；长度字段撒谎走同一条路径，不越界、不无限读。
- 语义字段做到**轨道级**：分辨率、帧率、采样率、位深、声道数、推算的平均码率。**不做**编码参数级（profile、level、色度采样、真实码率）。
- **字段词表**：统一词表只管**键名**（英文技术名 = 代码标识符 = 与规范逐字对照的术语）；各格式原生的字段名不丢，每个语义字段额外带 `source` 记着它来自哪个块的哪个字段。文件级 5 个键（`file_name`/`file_size`/`container_format`/`duration`/`overall_bitrate`）+ 轨道级 10 个键（`track_index`/`track_type`/`codec`/`width`/`height`/`frame_rate`/`sample_rate`/`bit_depth`/`channels`/`language`）。格式特有字段不进统一词表，挂在各格式自己的节点上。完整表见[统一语义字段词表](issues/08-field-vocabulary.md)。
- **标签**（MP4 的 `udta`/`meta`/`ilst`、FLAC 的 Vorbis Comment、MP3 的 ID3v2）**单独成区**，与技术属性、容器技术属性三者划清；标签的 key 保留英文原名（不翻译）。

**界面**

- **左右分栏**。左栏 = 语义字段视图（三个区段，顺序「文件级」→「轨道级」→「标签」）；右栏 = 结构树视图。hex 面板在**右栏下方**展开（选中块时出现，可折叠），标题显示该块的 type / offset / size。选中块时该块在树里高亮。
- **标签单独成区**，排在轨道级之后，与技术属性不混排。标签的 key 保留英文原名（不翻译）。
- 选中块时显示该块的原始 hex + ASCII 侧栏。
- 文件打开方式：拖放 + 文件选择器 + 多标签页。命令行参数不进 MVP。`Ctrl+Tab` 在标签间切换，关闭标签不影响其它标签。
- 每个标签页独立持有自己的解析状态；解析中、解析失败都有各自明确的视觉状态。
- 结构树用**虚拟滚动**；结构树的构建是**惰性展开**——初始只建到第一层，子块在用户展开时才解析。
- 导出：右键复制单个字段值 + 导出整个结果为 JSON（同时包含语义字段与结构树）。CSV 不做。
- 字段的**英文技术名永不翻译**（与规范逐字对照），中文只出现在界面显示名上。语义字段的来源（`read` 文件里直接写的 / `derived` 我们推算的）在界面上必须标出。

**构建与分发**

- GitHub Actions 矩阵 `windows-latest` + `macos-latest`；Flutter 版本**钉死 3.41.6**（对应本机 Dart 3.11.4），不用 `latest`；CI **不使用**本机的中国镜像环境变量（`PUB_HOSTED_URL` / `FLUTTER_STORAGE_BASE_URL`），保证本地与 CI 行为可比。触发条件为 push 到 `main`、打 tag、手动触发；**不在 PR 上跑**。
- 产物：Windows 打 zip（`flutter build windows --release` 产出的是目录），macOS 把 `.app` 打 tar.gz。命名带版本号与平台。macOS 产物**只保证构建成功**，不做自动冒烟。
- **双端都发 zip**：Windows 免安装 zip（解压即用，不写注册表、不需管理员权限）；macOS 把 `.app` 目录打 tar.gz，不做 .dmg（未公证的 app 本来就会被 Gatekeeper 拦，做成 .dmg 不改善这一点）。不做 Windows 安装包（Inno Setup / MSIX），不做自动更新。
- macOS 签名与公证不在本 effort 内（需付费 Apple Developer 账号 + 人工申请）。

**不做什么**

- 不解码、不播放、不转码。
- 不写回、不修改文件。
- 不做移动端与 Web 端。

## Testing Decisions

**什么样的测试算好**

只断言**外部可观察的行为**：解析出来的树、渲染出来的界面、导出的 JSON。不断言内部函数调用、不断言中间数据结构、不断言实现细节。解析器测试比的是"喂进去这些字节，应该得到这棵树"，而不是"代码走过了哪几个分支"。

**两条接缝**

1. **应用级接缝（最高层，主接缝）** —— widget test：启动真实应用，喂一个真实样本文件，断言渲染结果：语义字段视图里出现了哪些字段与值、结构树里出现了哪些块与偏移量、选中块后 hex 侧栏出现了什么。这条接缝覆盖"解析 → 模型 → 渲染"的完整链路，每个目标格式至少一条。
2. **解析器级接缝** —— 纯 Dart 测试（不依赖 Flutter），喂样本文件的字节，断言产出的节点树。与接缝 1 分离的理由：解析器的风险在数据正确性，不在 UI；把它压到应用层去测会写成脆弱的 UI 断言，而且"未知块如何降级"这类行为在 UI 层很难精确断言。这条接缝是断言密度的主要所在。

**明确不设第三条接缝** —— 不单独为字节读取层开一条接缝。偏移量与 64 位长度的正确性通过解析器级接缝间接覆盖，不额外增加接缝数量。

**优先使用现有接缝** —— 仓库目前唯一的接缝是 `flutter_test` 提供的 `testWidgets`，应用级接缝直接沿用它；解析器级接缝用 `package:test`（已随 `flutter_test` 传递依赖提供），不引入新依赖。

**先决条件（已满足）** —— 样本素材已按[测试素材获取与归档](issues/04-test-fixtures.md)落定：24 个样本在 `test/fixtures/`，两条接缝现在都有语料可用。

**既有测试的处理** —— 脚手架自带的计数器冒烟测试断言的是模板的 `MyApp` / `MyHomePage`，应用一旦重写就会失效，随第一批实现一并删除。

**测试目标** —— 每个目标格式（WAV、AIFF、FLAC、MP3、MP4、MOV、MKV、WebM）至少覆盖三类样本：正常样本、边界样本（最小尺寸、罕见但合法的参数组合）、损坏样本（截断、长度字段撒谎、未知块）。

**素材已就位** —— `test/fixtures/` 下 24 个样本，约 550 KB，全部由本机 ffmpeg 确定性生成（`dart run tool/gen_fixtures.dart` 可重现），不下载任何外部内容，因此随仓库提交，不需要 LFS。命名 `<格式>_<参数>.<类别>.<扩展名>`，类别为 `normal` / `edge` / `truncated` / `liesize`。**已知盲区**：素材只覆盖 ffmpeg 会写出的那种布局，真实世界里千奇百怪的文件（多个 `mdat` 的 MP4、`moov` 位于文件尾部的 MP4、fMP4 分片、非标准 mux 的 MKV）需要另行补充。
**块覆盖率清单** —— golden 文件防的是回归，防不住「解析器从一开始就漏了某个块」（golden 也是我们自己产的，漏了就是两边一起漏）。因此每个格式额外维护一份**必须支持的块类型清单**（人写规范，不继承别人的盲区），测试断言这些块都能在结构树里找到。例如 MP4 至少要能找到 `ftyp`/`moov`/`trak`/`mdia`/`minf`/`stbl`/`stsd`/`mdat`/`free`/`skip`/`uuid`。MediaTrace 对照基准**已决定不采纳**（CI 成本高、映射层是主要工作量、只单向可用），见[以 MediaTrace 作为结构树的离线校验基准](issues/12-mediatrace-offline-oracle.md)。

**已知盲区与对策** —— golden 文件防的是回归，防不住「解析器从一开始就漏了某个块」（golden 也是我们自己产的，漏了就是两边一起漏）。对策见下面的**块覆盖率清单**。MediaInfo 的 MediaTrace XML **已决定不采纳**作离线对照基准——CI 成本高、映射层是主要工作量、且只单向可用。

## Out of Scope

- **播放 / 转码 / 预览** —— 本工具只读元数据与结构，不解码媒体。**但播放是用户明确要求的能力，已规划为后续 effort**（[播放 + 从解析位置跳到播放位置](issues/28-playback-and-seek-to-position.md)）。MVP 阶段必须为此留好钩子：节点模型保留 `offset`/`size`、sample table 留在结构树里可访问、字节偏移一律是文件绝对偏移、时间一律用秒。
- **编辑 / 改写文件** —— 只读工具，不写回容器。
- **原生解析后端（FFmpeg / MediaInfoLib）** —— MVP 纯 Dart。**已定**：[调研结论](../../docs/research/03-mediainfo-ffprobe-depth.md) 确认前提成立（理由已改写为"现成方案给的是解读与文本，我们要的是原始结构与结构化数据"）。若将来要引，作为新 effort 重新评估，而不是在本 effort 内改道。
- **命令行 / 文件关联 / 系统右键菜单集成** —— MVP 只有 GUI。
- **macOS 签名与公证（notarization）** —— 需要付费 Apple Developer 账号，自成一个后续 effort。
- **移动端 / Web 端** —— 本 effort 只做 Windows + macOS 桌面。
- **CSV 导出、真实码率、profile/level 等编码参数级字段** —— 明确留到后续。
- **自动更新** —— 留在雾区，未决。

## Further Notes

**验收标准（Windows 与 macOS 统一）**：构建成功 + 手动点过主流程——启动应用 → 打开一个文件 → 同时看到语义字段与结构树 → 展开任意一个块并看到它的原始 hex。

**术语**：本规格使用仓库根目录 `GLOSSARY.md` 定义的词汇——容器、块、轨道、语义字段、结构树。注意"块"统一涵盖 ISO base media 的 box、RIFF 的 chunk、EBML 的 element 三种叫法；"语义字段"专指从容器结构解读出的技术属性，与"标签"是不同概念（两者边界**已定案**：标签单独成区。）。

**术语已定案**：`GLOSSARY.md` 已增补「标签 (Tag)」词条，「语义字段」的定义补上"不含标签"，"元数据 / Metadata"继续留在 avoid 词里——在这个项目里"元数据"若泛指一切就等于没有边界。

**与地图的关系**：本规格是 [media_info MVP 规格](map.md) 这张地图的终点产物。**12 张决策票已全部解完，结论已回写进本规格**——「未决事项」一节已清空，规格完整可实现。实现阶段的工作另开一组实现票跟踪。
