# 调研 03 — MediaInfo / ffprobe 到底能给出多深的结构

> 对应票：`.scratch/media-info-mvp/issues/03-mediainfo-ffprobe-depth.md`
> 依据：MediaArea 官方文档 + MediaInfoLib 源码；FFmpeg 官方文档 + 源码；两者各自的 LICENSE。只用一手材料。
> 术语依 `GLOSSARY.md`（容器 / 块 / 轨道 / 语义字段 / 结构树）。

## 结论摘要

**"纯 Dart 手写解析器"的前提，大体成立，但理由要改写。**

1. **FFmpeg 给不了**结构树。`av_dump_format` 只打印元数据、时长、章节、轨道，**完全没有 box 树**；mov demuxer 只在 `AV_LOG_TRACE` 级别打一行行 `type:'moov' parent:'root' sz: ...` 的日志，**没有字节偏移**；`AVIO_FLAG_TRACE` 在当前 master 里**已经不存在**；`ffprobe -show_packets/-show_format` 是**包级**（packet-level）而非块级。FFmpeg 明确出局。
2. **MediaInfo 能给出"带 offset 和 size 的块树"**——这就是 MediaArea 官方的 **MediaTrace** 格式（`<block offset="28" name="DocType" size="11">`），`mediainfo --Details=1 --Output=XML file.mov` 就能生成。所以"现成方案给不出任何带偏移的结构"这句话是**错的**。
3. **但它仍然救不了本项目的架构**，理由有三条，都比"没有结构树"更硬：
   - **保真度不对**：MediaTrace 是 **MediaInfo 自己的解读树**，块名是 MediaInfo 的语义标签（`Element_Name("File Type")`、`Element_Name("Free space")`），不是文件里字面的 fourcc / chunk id / EBML id。本产品的定位恰恰是"比 MediaInfo 更深地展示容器**原始**结构"，用它当结构引擎等于把"原始"换成"别人的解读"。
   - **拿不到原始 hex**：MediaTrace 的大块载荷只给 `(N bytes)` 摘要，叶子给的是解读后的值（十进制/文本），**没有 hex 下钻**。hex 视图仍然要我们自己按 offset/size 去读文件——也就是说 MediaInfo 替我们做的，恰好是我们不需要的那部分。
   - **拿不到结构化数据**：公开 C API（`MediaInfo_Option` / `MediaInfo_Inform`）只能给你**一整块预渲染的 XML 文本**；真正的树对象（`element_details::Element_Node`，带 `Pos`/`Size`）是 C++ 内部实现，官方 DLL API 不导出。要用就得自己 fork/改 MediaInfoLib 源码。
4. **代价**：MediaInfoLib 是 BSD-2-Clause（义务很轻），但是 C++ 大库，要 Windows + macOS 两套原生构建；FFmpeg 默认 LGPL v2.1+（可动态链接满足 §6(b)），但体积和 GPL 归属是另一回事。**macOS 侧无法从 Windows 交叉编译**——Flutter 工具本身直接拒绝：`"build macos" only supported on macOS hosts.`。

**给架构的落点**：保持"纯 Dart"不变，但把理由从"现成方案没有结构树"改成更准确的两条：
- 我们要的是**原始结构 + 原始字节**，两个现成方案都只给"解读"；
- 我们要的是**结构化数据**，两个现成方案都只给文本 blob。
最小可行替代方案见 §C.3。

---

## A. MediaInfo / MediaInfoLib

### A.1 "Details" / "Internal" 到底是什么

MediaInfo 有**两套**东西，名字容易混：

| 名字 | 实际是什么 | 源码依据 |
|---|---|---|
| `--Details=1` / `Option("Details")` | **"Trace" 的旧别名**，不是"多显示几个字段" | `MediaInfo_Config.cpp`：`if (Option_Lower==__T("details")) //Legacy for trace_level` → 转成 `Trace_Level` |
| `Trace_Level` | 一个 float 开关（默认 `0.0`）；>0 时启用 **trace 机制**并把输出格式切成 trace 专用格式 | `MediaInfo_Config.cpp`（`Trace_Level=(float32)0.0; Trace_Format=Trace_Format_Tree;`）与 `MediaInfo_Config.h`（`enum trace_Format { Trace_Format_Tree, Trace_Format_CSV, Trace_Format_XML, Trace_Format_MICRO_XML }`） |
| `MediaInfo_Internal::Details` | 一个 `string` 缓冲，解析器往里写**字段级明细文本**；可通过 `File_Details_StringPointer` 拿到 `指针:长度` | `MediaInfo_Internal.h`（`string Details;`）、`MediaInfo_Internal.cpp`（`Info->Init(&Config, &Details, &Stream, &Stream_More);` 与 `file_details_stringpointer` 分支） |

即：**"Details" 这个名字在 MediaInfo 里指的是 trace（内部结构追踪），不是字段表**；而库内部那个叫 `Details` 的成员才是字段级文本。

### A.2 粒度：MediaTrace 确实是带 offset 和 size 的块树

MediaArea 官方为这个能力定义了独立规范 **MediaTrace**（BSD-2-Clause，有 XSD 与数据字典），定义就是我们要的东西：

> MediaTrace is a technical report that expresses the binary architecture of a file as interpreted by MediaArea tools such as MediaInfo … In QuickTime parlance these blocks are called atoms, in AVI "chunks", and in Matroska, "elements". MediaTrace will attempt to parse apart each block into subdivisions and report on their contents. … MediaTrace will call it a `<block>`. In MediaTrace the contents of the block are called `<data>`.
> — <https://mediaarea.net/MediaTrace>

官方样例（含 offset / size / 嵌套）：

```xml
<block offset="28" name="DocType" info="matroska" size="11">
    <block offset="28" name="Header" size="3">
        <data offset="28" name="Name">642</data>
        <data offset="30" name="Size">8</data>
    </block>
    <data offset="31" name="Data">matroska</data>
</block>
```

生成方式（官方给出）：`mediainfo --Details=1 --Output=XML file.mov`。

源码层面完全对得上：

- 树节点结构 `element_details::Element_Node` 明确带 `int64u Pos; // Position of the element in the file` 和 `int64u Size; // Size of the element (including header and sub-elements)`，以及 `std::vector<Element_Node*> Children` —— <https://github.com/MediaArea/MediaInfoLib/blob/master/Source/MediaInfo/File__Analyze_Element.h>
- 打印成 XML 时逐字输出 `offset="Pos" name="Name" size="Size"`，叶子输出 `<data offset="…" name="…">value</data>` —— `Element_Node::Print_Xml`，<https://github.com/MediaArea/MediaInfoLib/blob/master/Source/MediaInfo/File__Analyze_Element.cpp>
- 叶子节点的 offset 是真字节位置：`node->Pos = File_Offset+Buffer_Offset+Element_Offset;`（`File__Analyze::Param`）—— <https://github.com/MediaArea/MediaInfoLib/blob/master/Source/MediaInfo/File__Analyze.h>
- 顶层文档由 `MediaInfo_Internal::Inform()` 产出：条件是 `Config.Trace_Level_Get() && Config.Trace_Format_Get()==Trace_Format_XML`，根元素写死为 `<MediaTrace xmlns="http://mediaarea.net/mediatrace" …>` —— <https://github.com/MediaArea/MediaInfoLib/blob/master/Source/MediaInfo/MediaInfo_Internal.cpp>
- 树格式（`Trace_Format_Tree`，人读）每行是 `偏移(hex)  缩进  名称  (N bytes)`。

**MP4/MOV 的覆盖度**：MediaInfo 的 MPEG-4 解析器把 box 层级**逐个建模**，`File_Mpeg4_Elements.cpp` 里就是一棵用宏写出来的 box 树（`LIST(moov)` / `ATOM_BEGIN` / `ATOM(moov_trak)` / `LIST(moov_trak_mdia_minf_stbl)` / …），宏定义在 `File__Analyze.h`（`#define ATOM(_ATOM)`、`#define LIST(_ATOM)`、`ATOM_BEGIN`/`ATOM_END`）。也就是说 **MediaInfo 的 MOV/MP4 trace 确实逐 box 给出层级**——<https://github.com/MediaArea/MediaInfoLib/blob/master/Source/MediaInfo/Multiple/File_Mpeg4_Elements.cpp>

### A.3 程序化可获取性：只能拿到"预渲染的 XML 文本"

公开 C API 的全部入口是 `MediaInfo_List_*` / `MediaInfo_*`（`MediaInfo_New`、`MediaInfo_Open`、`MediaInfo_Option`、`MediaInfo_Get`、`MediaInfo_Inform`、`MediaInfo_Count_Get` 等），见 <https://github.com/MediaArea/MediaInfoLib/blob/master/Source/MediaInfoDLL/MediaInfoDLL.cpp>。

逐个回答"能不能程序化拿到 per-box 结构"：

- `MediaInfo_Get(handle, Stream_General, 0, "Format")` 之类 → **不能**。`Get` 走的是 `MediaInfo_Internal::Get(...)`，返回的是**字段值**，按 stream kind + 参数名索引；结构树不在这条路径上。
- `MediaInfo_Option(handle, "Details", "1")` → 只是把 `Trace_Level` 设成 1（全局 `MediaInfo_Config`），随后 `MediaInfo_Inform(handle)` 返回的**整篇 XML 文本**（含 `<MediaTrace>` 树）。
- 想少拷贝一点 → `Option(handle, "File_Details_StringPointer")` 返回 `指针:长度`，但拿到的仍是 `Details` 那块**文本**（`MediaInfo_Internal.cpp` 明确返回 `Details.data()` 与 `Details.size()`），**不是树对象**。
- 真正的树对象 `element_details::Element_Node` 在 `MediaInfoLib` 的 C++ 内部（`File__Analyze_Element.h`），**不在 DLL 的 C ABI 导出面上**；要用它只能改 MediaInfoLib 源码 / 走 C++ 静态库内部接口（`element_details` 命名空间本身是 `MediaInfoLib` 的实现细节）。

**结论**：MediaInfo 能给结构树，但**只能以一段 XML 文本的形式**拿到，需要我们在 Dart 侧解析（好消息是它有官方 XSD：`https://mediaarea.net/mediatrace/mediatrace.xsd`，可作解析契约）。

### A.4 保真度：这是"MediaInfo 的解读树"，不是"文件的原始结构"

这是决定性的一条。MediaTrace 官方文档自己写得很清楚：

> MediaInfo's parsers determine how to label and dissect such data and therefore the MediaTrace values such as name or the granularity of the parsing many change over time.

源码一致：MPEG-4 解析器给 trace 节点起的是**语义名**，不是 fourcc —— `Element_Name("File Type")`（ftyp）、`Element_Name("Free space")`（free）、`Element_Name("JPEG 2000 header")`、`Element_Name("Item Property Container (parsing)")` 等（`File_Mpeg4_Elements.cpp`）。

对本项目意味着：

- 我们要展示"这个块在文件里叫 `moov` / `trak` / `stbl`"——MediaInfo 给的是"Movie"、"Track"、"Sample table"之类的解读名；**box 名字本身丢失了**。
- 未识别的块走 default 分支被跳过或记为 Unknown，**不等于"完整枚举文件里所有块"**。
- 大块载荷（mdat 等）只给 `(N bytes)` 摘要；**没有 hex**。MediaTrace 文档明确写："in lieu of displaying the full contents, it will be summarized by its size"。
- 叶子字段值是**解读后的十进制/文本**（`Param_Info` / `Element_Info` 路径），不是原始字节。

所以 MediaInfo 给的是"**别人眼里的文件结构**"，我们要的是"**文件本身的结构**"。产品的差异化定位（"比 MediaInfo 更深地展示容器原始结构"）与"用 MediaInfo 当结构引擎"是冲突的。

### A.5 许可与集成代价

**许可：BSD 2-Clause**，义务极轻 —— 二进制分发时"reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution"（保留版权声明 + 免责声明），源码分发时保留原声明即可。无 copyleft、无"必须提供源码/允许重链接"的要求。
— <https://github.com/MediaArea/MediaInfoLib/blob/master/LICENSE>（同 <https://mediaarea.net/MediaTrace> 页面底部也附了同一份 BSD-2-Clause）

**代价 1：体积与编译开关。** trace 机制受编译期宏 `MEDIAINFO_TRACE` 控制：`Setup.h` 里默认 `MEDIAINFO_TRACE 1`，但 `MEDIAINFO_MINIMIZESIZE` / `MEDIAINFO_MINIMAL_YES` 会强制 `MEDIAINFO_TRACE_NO`——即"精简体积的构建会把 trace 编译掉"。同时 trace 会让解析显著变慢（官方 changelog 提到 FFV1 "avoiding by default a too verbose trace"），并有 "Trace: fix freeze with some files" 这类历史 bug。官方 changelog 也确认 trace 输出"only if compiled with trace feature"（<https://github.com/MediaArea/MediaInfo/blob/master/History_CLI.txt>）。

**代价 2：它是 C++ 大库。** MediaInfoLib = MediaInfoLib + ZenLib，纯 C++；要接进 Flutter 桌面 = Windows 一套原生构建 + macOS 一套原生构建 + 一个 C ABI 薄壳（现成的 `MediaInfoDLL` C API 正好可以当这层壳）。这会推翻 map 里"**MVP 不引入任何原生依赖**"这条既定前提。

**代价 3：构建系统不统一。** MediaInfoLib 官方构建以 MSVC 工程文件 / autotools 为主，`Source/` 下**没有**顶层 `CMakeLists.txt`（404），也就是说要接 Flutter 的 CMake 链路得自己补一份构建脚本。

**代价 4：macOS 必须原生构建。** 见 §B.6 末尾（Flutter 工具硬性拒绝非 macOS 主机；且 macOS 侧还需要 Xcode/clang 与（未来的）签名/公证流程）。

---

## B. FFmpeg / ffprobe

### B.1 `av_dump_format` 没有 box 树（票面假设不成立）

`av_dump_format` 的实现（`libavformat/dump.c`）只输出：容器名与 URL、`ic->metadata`、Duration / start / bitrate、Chapters、Programs、以及每条 stream 的格式串（`avcodec_string`）+ stream metadata + side data。**没有任何盒子/块层级输出**，与容器类型无关（mov/mp4 也一样）。
— <https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/dump.c>（`void av_dump_format(AVFormatContext *ic, int index, const char *url, int is_output)`）

### B.2 mov demuxer 的 TRACE 日志：有层级，没有偏移

`libavformat/mov.c` 里唯一接近"结构 dump"的东西，是 `mov_read_default()` 里的一行日志：

```c
av_log(c->fc, AV_LOG_TRACE, "type:'%s' parent:'%s' sz: %"PRId64" %"PRId64" %"PRId64"\n",
       av_fourcc2str(a.type), av_fourcc2str(atom.type), a.size, total_size, atom.size);
```

— <https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/mov.c>

粒度解读：

- 有 **type + parent type**，即父子关系（靠 `parent` 字段能拼出树）；
- 三个 size 分别是 **本 box 大小**、**父 box 内累计偏移**、**父 box 大小**——**都不是文件的绝对字节偏移**；
- 只覆盖 FFmpeg 自己会走进去的容器盒（`moov/trak/mdia/minf/stbl/...`），叶子盒走各自的 `mov_read_xxx` 后**不再进入 `mov_read_default`**，所以 `stsd`/`avcC` 之类的内部不会被逐个列出；
- 是 **log 文本**，不是数据结构。

要拿到它只能 `-loglevel trace` 抓 stderr，程序化没有出口。

### B.3 `AVIO_FLAG_TRACE` 已经不存在

票面提到的 `AVIO_FLAG_TRACE`：当前 master 的 `libavformat/avio.h` 里，URL 打开模式只定义了 `AVIO_FLAG_READ` / `AVIO_FLAG_WRITE` / `AVIO_FLAG_READ_WRITE` / `AVIO_FLAG_NONBLOCK` / `AVIO_FLAG_DIRECT`，**没有 TRACE**；`avio_alloc_context()` 也不再接受 `flags` 参数。对应的 `libavformat/aviobuf.c` 中已无任何 trace 路径。
— <https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/avio.h>、<https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/aviobuf.c>

而且它本来就是**I/O 层 trace**（每次 read/seek 的位置），不是容器结构。

### B.4 `ffprobe` 的 JSON 是包级，不是块级

`ffprobe` 的 section 只有 `FORMAT` / `STREAM` / `PACKET` / `FRAME` / `CHAPTER` / `PROGRAM_STREAM` / `STREAM_GROUP_STREAM` 等；`-show_packets` 给的是包的时间戳、大小、**包在文件中的位置（pos）**，`-show_data` 给的是**包载荷**的 hexdump（`-data_dump_format` 默认 `xxd`）。**没有任何 box/atom 级别的 section。**
— <https://ffmpeg.org/ffprobe.html>（`-show_format` / `-show_packets` / `-show_data` / `-show_entries` 各节）

`AVFormatContext` 上也没有结构出口：`MOVContext` 是 demuxer 的私有数据（`st->priv_data`），不导出。

### B.5 许可：LGPL 还是 GPL，取决于 configure

- 默认 **LGPL v2.1+**；只有显式 `--enable-gpl`（或链接 GPL 库如 libx264/x265）才会变成 **GPL v2+**。
  — <https://github.com/FFmpeg/FFmpeg/blob/master/LICENSE.md>
- **对发布应用的义务**（LGPL v2.1 §6）：
  - §6(b) **动态链接**：用 shared library 机制链接，用户可替换库 → **不需要**公开我们的源码；
  - §6(a) 静态链接则要提供库源码 + 工程的 object 文件，让用户能重新链接；
  - §6(c) 或提供书面要约（≥3 年）；
  - 共同义务：**随附 LGPL 副本 + 显著声明"本产品使用了该库且受 LGPL 覆盖"**。
  — <https://github.com/FFmpeg/FFmpeg/blob/master/COPYING.LGPLv2.1>（第 6 条）
- 我们的场景（只读元数据、不解码）其实**不需要 libavcodec**，可以只链 libavformat + libavutil，并关闭 GPL 组件。

### B.6 体积与集成代价

- **体积（估算，本机未实测，必须实测）**：全量构建的 `libavcodec` 是几十 MB 量级，`libavformat`/`libavutil` 是几 MB 量级；但我们的用途只需要 **demuxer**，用 `--disable-everything --enable-demuxer=mov,matroska,wav,aiff,flac,mp3 --disable-decoders --disable-parsers --enable-protocol=file` 这类精简配置后，`libavformat` + `libavutil` 的体积是**几 MB 量级**（需在目标平台实测后填数）。
  — 配置项依据 <https://github.com/FFmpeg/FFmpeg/blob/master/configure>（`--disable-everything` / `--enable-demuxer` / `--disable-decoders`）
- **集成代价**：C 库，直接可用 `dart:ffi` 绑定，比 MediaInfoLib 的 C++ 简单；但仍需 Windows（CMake）+ macOS（Xcode / CocoaPods）两套构建与两套产物。
- **macOS 无法从 Windows 交叉编译**：Flutter 工具在 `build macos` 里显式判断主机系统，不在 macOS 上直接报错退出——

  ```dart
  if (!supported) {
    throwToolExit('"build macos" only supported on macOS hosts.');
  }
  ```
  — <https://github.com/flutter/flutter/blob/master/packages/flutter_tools/lib/src/commands/build_macos.dart>

  同理，任何 macOS 侧的 `.dylib`/framework 都必须在 macOS 主机上用 Xcode 工具链产出（签名/公证另议）。**本仓库当前只有 Windows 与 macOS 两个目标，这意味着引入任一原生库都会立刻引入"必须有 macOS 构建机"的硬约束**（仓库 `AGENTS.md` 已记录 `macos/` 需要 Mac）。

---

## C. 综合结论与对架构的影响

### C.1 能不能交付"可展开的块树 + 偏移量 + 长度 + 下钻到原始 hex"？

| 能力 | MediaInfo（MediaTrace） | FFmpeg / ffprobe |
|---|---|---|
| 块级层级树 | ✅ 有（`<block>` 嵌套） | ❌ 无（`av_dump_format` 无；TRACE 日志无绝对偏移） |
| 每块偏移量 | ✅ `offset="..."` | ❌（只有 parent 累计偏移） |
| 每块长度 | ✅ `size="..."` | ⚠️ 只有大小，无偏移，凑不成"选中即定位" |
| 结构化（可编程）获取 | ❌ 只有预渲染 XML 文本 | ❌ 只有 log 文本 / 包级 JSON |
| 原始 hex 下钻 | ❌（大块只给 `(N bytes)` 摘要） | ⚠️ 只有 `-show_data` 的**包载荷** hex，不是任意块 |
| 块名是否是文件里的原始名字 | ❌（MediaInfo 的语义标签） | — |
| 未识别块是否原样呈现 | ❌（走 default 分支） | — |

**MediaInfo = 部分可行（是"解读树"，不是"原始结构"）；FFmpeg = 不可行。**

### C.2 "纯 Dart 手写解析器"还剩多少理由？

**前提成立（要改写理由），而不是被推翻。**

- 被推翻的部分：不能说"现成方案给不出带偏移的块树"——MediaInfo 的 MediaTrace 确实给得出（offset + size + 嵌套）。
- 仍然成立的部分（三条更硬的理由）：
  1. **保真度**：我们要的是文件里字面的块类型与层次；MediaTrace 是 MediaInfo 的解读，块名被语义标签替换，未知块被折叠。
  2. **原始字节**：hex 视图必须我们自己按 offset/size 读文件；MediaInfo 不提供原始字节视图。
  3. **数据形态**：两个方案都只给文本 blob，没有结构化 API；我们要的是一个能直接喂给 UI 的统一节点模型（票 01/02 的方向），而不是解析第三方 XML/日志。
- 结论：**保持"纯 Dart、零原生依赖"的既定前提**，但把论证从"现成方案没有结构深度"改为"现成方案给的是*解读*与*文本*，我们要的是*原始结构*与*结构化数据*；且引入它们会把 MVP 从零原生依赖变成跨双平台的 C/C++ 原生工程，代价与收益不成比例"。

### C.3 如果要混合，最小可行替代方案（骨架）

保持零原生依赖，把"结构"和"语义"分成两件事：

1. **结构树（自己写，很薄）**：每种容器只需要一个**块头扫描器**，产出统一节点模型（票 01 的节点模型）：
   - ISO BMFF（MP4/MOV/JPEG2000…）：8/16 字节 box 头（size + type；size==1 走 64 位扩展；size==0 到文件尾），容器型 box 递归下降；
   - RIFF（WAV/AVI）：`id` + `LE32 size` + 负载，容器型递归（`LIST`/`RIFF` 带 form type）；
   - EBML（Matroska/WebM）：element id + VINT size（含"未知长度"哨兵）递归；
   - FLAC：元数据块（last-metadata-block 标志 + 24 bit 长度）；
   - MP3：帧头（ID3v2 前缀 + 帧序列）——这一档没有真正的"块树"，按轨道/帧列表呈现即可。
   每个节点产出：**type（原始名字）+ offset + size + children**。原始 hex 由 Dart 侧按 offset/size 从文件读取（票 06）。
2. **语义字段**：从同一棵树上**推导**（时长、采样率、位深、声道、分辨率、帧率、推算码率），即 map 里写明的"轨道级字段深度"。规则比"通用解析"少得多，但能保证字段与结构树**位置一致**（这正是 MediaInfo 做不到的）。
3. **（可选、后续 effort）交叉校验**：真要引 MediaInfo，只把它当**离线校验工具**（CI 里对比字段值），不进产品二进制；它的 MediaTrace XML 也可以拿来当"我们的结构树是否漏块"的对照基准（官方有 XSD 与样例：`https://mediaarea.net/mediatrace/mediatrace.xsd`）。

### C.4 需要在后续票里处理的未验证项

- MediaInfo 各格式的 trace 实际覆盖度（哪些容器逐块、哪些折叠）需要拿真实样本跑一遍 `mediainfo --Details=1 --Output=XML` 才能量化；本票只验证了机制与 MP4 的建模方式。
- MediaInfoLib 的可裁剪构建与体积（`MEDIAINFO_MINIMIZESIZE` vs `MEDIAINFO_TRACE`）未实测。
- FFmpeg 精简构建（demuxer-only）的实际产物体积未实测。
- 若将来真接原生库：FFmpeg 的 LGPL §6 动态链接方案 vs MediaInfoLib 的 BSD 静态/动态链接，两者在 Flutter 桌面打包链路里的落地方式需要单独验证。

---

## 引用清单（全部一手来源）

**MediaInfo / MediaArea**
- MediaTrace 官方说明（格式定义、样例、`--Details=1 --Output=XML` 用法、BSD-2-Clause）— <https://mediaarea.net/MediaTrace>
- MediaTrace XSD — <https://mediaarea.net/mediatrace/mediatrace.xsd>
- MediaInfoLib LICENSE（BSD 2-Clause）— <https://github.com/MediaArea/MediaInfoLib/blob/master/LICENSE>
- `MediaInfo_Config.cpp`（`details` → `trace_level` 别名；`Trace_Level`/`Trace_Format` 默认值）— <https://github.com/MediaArea/MediaInfoLib/blob/master/Source/MediaInfo/MediaInfo_Config.cpp>
- `MediaInfo_Config.h`（`trace_Format` 枚举、`Trace_Level_Set/Get`）— <https://github.com/MediaArea/MediaInfoLib/blob/master/Source/MediaInfo/MediaInfo_Config.h>
- `MediaInfo_Internal.cpp`（`Details` 成员与 `file_details_stringpointer`；`Inform()` 产出 `<MediaTrace>`）— <https://github.com/MediaArea/MediaInfoLib/blob/master/Source/MediaInfo/MediaInfo_Internal.cpp>
- `MediaInfo_Internal.h`（`string Details;`、`Get`/`Option`/`Inform` 签名）— <https://github.com/MediaArea/MediaInfoLib/blob/master/Source/MediaInfo/MediaInfo_Internal.h>
- `File__Analyze_Element.h`（`Element_Node::Pos`/`Size`/`Children`）— <https://github.com/MediaArea/MediaInfoLib/blob/master/Source/MediaInfo/File__Analyze_Element.h>
- `File__Analyze_Element.cpp`（`Print_Xml` 输出 `offset`/`name`/`size`；`Print_Tree`）— <https://github.com/MediaArea/MediaInfoLib/blob/master/Source/MediaInfo/File__Analyze_Element.cpp>
- `File__Analyze.h`（`Param()` 计算 `node->Pos`；`ATOM`/`LIST`/`ATOM_BEGIN`/`ATOM_END` 宏）— <https://github.com/MediaArea/MediaInfoLib/blob/master/Source/MediaInfo/File__Analyze.h>
- `Multiple/File_Mpeg4_Elements.cpp`（MP4 box 层级 DSL；`Element_Name("File Type")` 等语义标签）— <https://github.com/MediaArea/MediaInfoLib/blob/master/Source/MediaInfo/Multiple/File_Mpeg4_Elements.cpp>
- `Setup.h`（`MEDIAINFO_TRACE` 默认 1；`MEDIAINFO_MINIMIZESIZE` → `MEDIAINFO_TRACE_NO`）— <https://github.com/MediaArea/MediaInfoLib/blob/master/Source/MediaInfo/Setup.h>
- `MediaInfoDLL.cpp`（公开 C API 全集）— <https://github.com/MediaArea/MediaInfoLib/blob/master/Source/MediaInfoDLL/MediaInfoDLL.cpp>
- MediaInfo changelog（trace 仅在带 trace 特性编译时可用；FFV1 trace 体积/性能；Trace 历史缺陷）— <https://github.com/MediaArea/MediaInfo/blob/master/History_CLI.txt>

**FFmpeg**
- `LICENSE.md`（默认 LGPL v2.1+；`--enable-gpl` 变 GPL；外部库兼容性）— <https://github.com/FFmpeg/FFmpeg/blob/master/LICENSE.md>
- `COPYING.LGPLv2.1`（§5/§6：源码提供义务、§6(b) 动态链接、§6(c) 书面要约、声明义务）— <https://github.com/FFmpeg/FFmpeg/blob/master/COPYING.LGPLv2.1>
- `libavformat/dump.c`（`av_dump_format` 的实际输出内容）— <https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/dump.c>
- `libavformat/mov.c`（`mov_read_default` 的 TRACE 日志行）— <https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/mov.c>
- `libavformat/avio.h`（无 `AVIO_FLAG_TRACE`；`avio_alloc_context` 无 flags）— <https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/avio.h>
- `libavformat/aviobuf.c`（无 trace 实现）— <https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/aviobuf.c>
- ffprobe 官方文档（section 列表、`-show_data`/`-show_packets`/`-show_entries`）— <https://ffmpeg.org/ffprobe.html>
- `configure`（`--disable-everything` / `--enable-demuxer` / `--disable-decoders`）— <https://github.com/FFmpeg/FFmpeg/blob/master/configure>

**Flutter**
- `build_macos.dart`（`"build macos" only supported on macOS hosts.`）— <https://github.com/flutter/flutter/blob/master/packages/flutter_tools/lib/src/commands/build_macos.dart>
- 桌面支持与插件 — <https://docs.flutter.dev/platform-integration/desktop>
- FFI / build hook（含 CMakeLists.txt / .podspec 的历史工作流说明）— <https://docs.flutter.dev/platform-integration/bind-native-code>
