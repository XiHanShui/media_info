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

## 未决事项（实现到这些区域前需先解票）

| 决策 | 票 | 影响什么 |
|---|---|---|
| 统一节点模型与双视图的数据来源 | [统一节点模型与双视图的数据来源](issues/01-unified-node-model.md) | 节点 schema、字段挂哪一级、结构树是否惰性展开 |
| 容器格式能否用声明式规格表描述 | [容器格式能否用声明式规格表描述](issues/02-declarative-parsers.md) | 解析层是"N 个解析器"还是"N 张表 + 1 个引擎" |
| 测试素材获取与归档 | [测试素材获取与归档](issues/04-test-fixtures.md) | 接缝能跑起来的前提：样本从哪来、怎么放 |
| 字节访问与大文件策略 | [字节访问与大文件策略](issues/06-byte-access-large-files.md) | 随机访问 vs 映射 vs 流式；64 位长度；截断文件行为 |
| 界面布局与多文件交互 | [界面布局与多文件交互](issues/07-ui-layout-prototype.md) | 分栏形态、hex 侧栏位置、标签页组织 |
| 统一语义字段词表 | [统一语义字段词表](issues/08-field-vocabulary.md) | 字段的英文技术名、中文显示名、跨格式归一方式 |
| 标签 / 元数据与语义字段的边界 | [标签 / 元数据与语义字段的边界](issues/09-tag-vs-field-boundary.md) | MP4 udta/ilst、FLAC Vorbis Comment、ID3 要不要看 |
| 以 MediaTrace 作为结构树的离线校验基准 | [以 MediaTrace 作为结构树的离线校验基准](issues/12-mediatrace-offline-oracle.md) | 要不要拿 MediaInfo 的输出当"有没有漏块"的对照基准 |
| CI 双平台构建 | [CI 双平台构建](issues/10-ci-dual-platform.md) | 构建矩阵、产物形态、缓存 |
| 分发形态与签名 | [分发形态与签名](issues/11-distribution-form.md) | 用户最终拿到 zip 还是安装包 |

**其中三张是实现的前置**：节点模型、测试素材、字节访问策略。其余可在对应模块开工前补齐。

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

## Implementation Decisions

**平台与技术栈**

- Flutter 桌面应用，目标是 Windows 与 macOS。Windows 优先推进，macOS 随后由用户在自己的 Mac 上验证。
- Dart SDK 约束不低于 3.10（代码使用 Dart 3 的点简写语法）；Flutter 版本钉在 3.41.6 stable，不使用 `latest`。
- 界面文案中文；代码内部标识符、字段名、块类型名一律英文，以便与格式规范逐字对照。

**解析层**

- 每种格式一个解析器，纯 Dart 手写，不引入 C/C++、FFmpeg 或 MediaInfoLib。**理由**：我们要的是**原始结构 + 结构化数据**；现成方案给的都是**解读 + 文本 blob**——MediaInfo 的 MediaTrace 虽是带 offset 与 size 的真块树，但那是它自己的语义解读树（块名被换成 `Element_Name("File Type")` 之类的标签、未知块被折叠、大块只给 "(N bytes)" 摘要、**无 hex**），而且只能拿到一整块预渲染的 XML 文本，真正的树对象在 C++ 内部不导出；FFmpeg 则根本没有块树（`av_dump_format` 只打印元数据，`AVIO_FLAG_TRACE` 已从 master 移除）。引入任一原生库还会立刻加上"必须有 macOS 构建机"的硬约束——`flutter build macos` 在非 macOS 主机上直接报错退出。详见 [调研结论](../../docs/research/03-mediainfo-ffprobe-depth.md)。
- 解析器通过一个注册表接入，扩展点是"新增一个解析器 + 一张格式描述"，不需要改动引擎骨架。
- 每种容器只写一个**块头扫描器**，产出统一节点模型的最小四元组——`type`（文件里字面的块类型名）+ `offset` + `size` + `children`——语义字段再从同一棵树上**推导**，这样字段与结构树的位置天然一致。各容器的块头布局已知：ISO BMFF 是 8/16 字节 box 头（`size == 1` 走 64 位扩展，`size == 0` 到文件尾）、RIFF 是 `id + LE32 size`、EBML 是 element id + VINT size（含未知长度哨兵）、FLAC 是元数据块（last-metadata-block 标志 + 24 位长度）、MP3 是帧序列（**这一档没有真正的块树**，按帧列表呈现）。原始 hex 由 Dart 侧按 offset/size 自行从文件读取。
- 节点模型统一承载两种视图：结构树与语义字段从同一份数据派生，节点携带名称、类型、偏移量、长度、字段值与子节点（确切 schema 待[统一节点模型与双视图的数据来源](issues/01-unified-node-model.md)定）。
- 解析层是"N 个命令式解析器"还是"N 张声明式规格表 + 1 个通用引擎"，待[容器格式能否用声明式规格表描述](issues/02-declarative-parsers.md)结论；这个选择显著影响后续所有实现的工作量。
- 字节读取策略、64 位长度（`largesize` / `co64`）、以及大文件下的惰性展开行为，待[字节访问与大文件策略](issues/06-byte-access-large-files.md)定。
- 未知块与损坏文件必须降级展示，不能让整个解析失败——已读到的部分结构仍然呈现，错误以明确形式给出。
- 语义字段做到**轨道级**：分辨率、帧率、采样率、位深、声道数、推算的平均码率。**不做**编码参数级（profile、level、色度采样、真实码率）。
- 语义字段的英文技术名与中文显示名、跨格式归一规则，待[统一语义字段词表](issues/08-field-vocabulary.md)定。
- 标签类内容（MP4 的 `udta`/`meta`/`ilst`、FLAC 的 Vorbis Comment、MP3 的 ID3）与语义字段的边界，待[标签 / 元数据与语义字段的边界](issues/09-tag-vs-field-boundary.md)定。

**界面**

- 两个视图并存：语义字段 + 结构树。分栏形态（左/右、上/下、Tab）与 hex 侧栏位置，待[界面布局与多文件交互](issues/07-ui-layout-prototype.md)原型确定。
- 选中块时显示该块的原始 hex + ASCII 侧栏。
- 文件打开方式：拖放 + 文件选择器 + 多标签页。命令行参数不进 MVP。
- 每个标签页独立持有自己的解析状态；解析中、解析失败都有各自明确的视觉状态。
- 结构树在条目极多时保持可滚动（虚拟化 / 惰性展开，由布局票与字节访问票共同定）。
- 导出：右键复制单个字段值 + 导出整个结果为 JSON。CSV 不做。

**构建与分发**

- GitHub Actions 上构建 Windows 与 macOS 两个平台；Flutter 版本钉死不用 `latest`；CI 不使用本机的中国镜像环境变量。
- 用户最终拿到的产物形态（Windows 免安装 zip 还是安装包、macOS 的 .app zip 还是 .dmg）待[分发形态与签名](issues/11-distribution-form.md)定。
- macOS 签名与公证不在本 effort 内。

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

**先决条件** —— 没有样本文件，两条接缝都跑不起来。样本清单、来源、存放位置与命名规范待[测试素材获取与归档](issues/04-test-fixtures.md)定；该票未落定前不要开始写解析器，否则验证会退化成"拿手头随便一个文件试试"。

**既有测试的处理** —— 脚手架自带的计数器冒烟测试断言的是模板的 `MyApp` / `MyHomePage`，应用一旦重写就会失效，随第一批实现一并删除。

**测试目标** —— 每个目标格式（WAV、AIFF、FLAC、MP3、MP4、MOV、MKV、WebM）至少覆盖三类样本：正常样本、边界样本（最小尺寸、罕见但合法的参数组合）、损坏样本（截断、长度字段撒谎、未知块）。

**已知的覆盖盲区** —— 用自己产的 golden 文件做基准，有一个结构性盲区：**"解析器从一开始就漏了某个块"这类 bug 测不出来**，因为 golden 也是我们自己产的，漏了就是两边一起漏。是否引入 MediaInfo 的 MediaTrace XML 作**离线**对照基准（只作 CI 里的对照工具，不进产品二进制；且只单向可用——"MediaTrace 有、我们没有"是我们错，"它漏了我们有"不一定），待 [以 MediaTrace 作为结构树的离线校验基准](issues/12-mediatrace-offline-oracle.md) 定。

## Out of Scope

- **播放 / 转码 / 预览** —— 本工具只读元数据与结构，不解码媒体。
- **编辑 / 改写文件** —— 只读工具，不写回容器。
- **原生解析后端（FFmpeg / MediaInfoLib）** —— MVP 纯 Dart。**已定**：[调研结论](../../docs/research/03-mediainfo-ffprobe-depth.md) 确认前提成立（理由已改写为"现成方案给的是解读与文本，我们要的是原始结构与结构化数据"）。若将来要引，作为新 effort 重新评估，而不是在本 effort 内改道。
- **命令行 / 文件关联 / 系统右键菜单集成** —— MVP 只有 GUI。
- **macOS 签名与公证（notarization）** —— 需要付费 Apple Developer 账号，自成一个后续 effort。
- **移动端 / Web 端** —— 本 effort 只做 Windows + macOS 桌面。
- **CSV 导出、真实码率、profile/level 等编码参数级字段** —— 明确留到后续。
- **自动更新** —— 留在雾区，未决。

## Further Notes

**验收标准（Windows 与 macOS 统一）**：构建成功 + 手动点过主流程——启动应用 → 打开一个文件 → 同时看到语义字段与结构树 → 展开任意一个块并看到它的原始 hex。

**术语**：本规格使用仓库根目录 `GLOSSARY.md` 定义的词汇——容器、块、轨道、语义字段、结构树。注意"块"统一涵盖 ISO base media 的 box、RIFF 的 chunk、EBML 的 element 三种叫法；"语义字段"专指从容器结构解读出的技术属性，与"标签"是不同概念（两者边界仍待定）。

**已知的一处待修**：`GLOSSARY.md` 目前把"元数据 / Metadata"列为"语义字段"的 avoid 词，这个划法在[标签 / 元数据与语义字段的边界](issues/09-tag-vs-field-boundary.md)定案前是暂定的。

**与地图的关系**：本规格是 [media_info MVP 规格](map.md) 这张地图的终点产物。地图上的票全部解完、其结论回写进本规格后，本规格才算完整；在此之前，「未决事项」一节列出的区域带 TBD 标记。
