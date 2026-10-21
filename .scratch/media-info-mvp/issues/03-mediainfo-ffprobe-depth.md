# 调研：MediaInfo / ffprobe 到底能给出多深的结构

Type: research
Status: resolved
Blocked by:

## Question

MVP 已经决定"纯 Dart 自研解析器"，但这个决定的前提是**现成方案给不了我们要的结构深度**。本票负责验证这个前提是否成立。

要回答的：

- **MediaInfoLib** 暴露的 "Details" / "Internal" 标签，粒度到底是什么？是否包含每个 box / element 的**偏移量与长度**？还是只有字段级的解读 + 一个文本化的树？
- **FFmpeg** 的 `mov` demuxer 在 `av_dump_format` 里打印的结构，粒度如何？**能否程序化获取**（而不只是人读的 dump）——`AVIO_FLAG_TRACE`、demuxer 的私有选项、或 `AVFormatContext` 上有没有结构化的内部结构出口？
- 如果两者都拿不到"带偏移量、大小、可展开、还能看原始 hex 的树"，那"自研"的理由就成立；**如果拿得到**，自研还剩多少理由？
- 无论结论如何，两条路的**集成代价**：MediaInfoLib 是 BSD 许可的 C++ 大库（要接进 Flutter 桌面就意味着 Windows CMake + macOS CocoaPods 两套原生构建）；FFmpeg 的 LGPL/GPL 归属取决于构建配置，打包体积另算。把这些代价量化（构建复杂度、体积增量、macOS 交叉编译可行性）。

**依据**：MediaInfo 官方文档与其源码、FFmpeg 官方文档与源码、两者各自的许可文件。

**产出**：`docs/research/03-mediainfo-ffprobe-depth.md`，结论摘要回填本票 `## Answer`。

**注意**：本票只做调研，**不改架构决定**。如果结论动摇了"纯 Dart"的既定前提，那是走地图的"新增票"路径（重新评估），而不是在本 effort 内悄悄改道。

## Answer

完整调研见 [docs/research/03-mediainfo-ffprobe-depth.md](../../../docs/research/03-mediainfo-ffprobe-depth.md)（一手来源，逐条带引用）。

**结论：前提成立，但要改写理由。** 被推翻的是"现成方案给不出带偏移的结构"这句话。

**FFmpeg 彻底出局**（三条硬证据）：

- `av_dump_format` 的实现（`libavformat/dump.c`）只打印元数据、时长、章节、轨道，**根本没有 box 树**，与容器类型无关。
- mov demuxer 唯一接近结构 dump 的东西是 `mov_read_default()` 里一行 `AV_LOG_TRACE` 日志——有 type/parent/size，但三个 size 都不是文件的绝对字节偏移；而且它是 **log 文本**，没有程序化出口。
- 票面假设的 `AVIO_FLAG_TRACE` **在当前 master 里已经不存在**（`libavformat/avio.h` 只剩 READ/WRITE/READ_WRITE/NONBLOCK/DIRECT）。`ffprobe` 的 JSON 是包级，不是块级。

**MediaInfo 能给出真的块树**——MediaArea 官方的 **MediaTrace** 格式（`<block offset="28" name="DocType" size="11">`），`mediainfo --Details=1 --Output=XML` 即可生成；MediaInfoLib 源码里 `element_details::Element_Node` 确实带 `Pos`/`Size`/`Children`。所以"没有结构树"是错的。

**但它仍然救不了本项目，三条更硬的理由**：

1. **保真度不对**：MediaTrace 是 MediaInfo **自己的解读树**，块名被换成它的语义标签（`Element_Name("File Type")` 之于 `ftyp`），未知块走 default 分支被折叠，mdat 之类只给 `(N bytes)` 摘要——**拿不到文件里字面的块类型，也拿不到完整枚举**。产品定位恰恰是"比 MediaInfo 更深地展示容器**原始**结构"，用它当结构引擎等于把"原始"换成"别人的解读"。
2. **拿不到原始 hex**：MediaTrace 不提供原始字节，hex 视图仍要我们自己按 offset/size 读文件——它替我们做的恰好是我们不需要的那部分。
3. **拿不到结构化数据**：公开 C API 只能给你**一整块预渲染的 XML 文本**；真正的树对象在 C++ 内部（`element_details` 命名空间是实现细节，不在 DLL 的 C ABI 导出面上），要用就得改 MediaInfoLib 源码。

**代价**：MediaInfoLib 是 BSD-2-Clause（义务很轻），但是 C++ 大库，接进 Flutter 桌面 = Windows 一套原生构建 + macOS 一套原生构建，而它 `Source/` 下**没有顶层 CMakeLists.txt**，得自己补构建脚本。FFmpeg 默认 LGPL v2.1+（动态链接满足 §6(b) 即可不公开我们的源码），但同样要两套原生构建与产物。

**新发现的硬约束**：`flutter build macos` 在非 macOS 主机上直接报错退出（`"build macos" only supported on macOS hosts.`）。**引入任何一个原生库，都会立刻给 MVP 加上"必须有 macOS 构建机"的硬约束。**

**理由改写后的表述**（替换原先的说法）：

> 我们要的是**原始结构 + 结构化数据**；两个现成方案给的都是**解读 + 文本 blob**。且引入它们会把 MVP 从"零原生依赖"变成"跨双平台的 C/C++ 原生工程"，代价与收益不成比例。

**最小可行骨架（供后续票直接取用）**：每种容器只写一个**块头扫描器**，产出统一节点模型的 `type（原始名字）+ offset + size + children`——ISO BMFF 8/16 字节 box 头（size==1 走 64 位扩展，size==0 到文件尾）、RIFF 的 `id + LE32 size`、EBML 的 element id + VINT size（含未知长度哨兵）、FLAC 的 metadata block、MP3 的帧序列（这一档没有真正的块树，按帧列表呈现）。**语义字段从同一棵树上推导**，这样字段与结构树位置天然一致——这正是 MediaInfo 做不到的。

**额外收获**：MediaTrace 有官方 XSD 与样例（<https://mediaarea.net/mediatrace/mediatrace.xsd>），可以拿来做我们结构树"有没有漏块"的**离线校验基准**（只作 CI 里的对照工具，不进产品二进制）。这条另开一票： [以 MediaTrace 作为结构树的离线校验基准](12-mediatrace-offline-oracle.md)。

**对既有票的影响**：

- [统一节点模型与双视图的数据来源](01-unified-node-model.md)：新增先例——块扫描器产出的最小四元组 `type + offset + size + children`。
- [字节访问与大文件策略](06-byte-access-large-files.md)：新增先例——各容器的块头布局，以及"hex 由 Dart 侧按 offset/size 自行读取"这一职责划分。

