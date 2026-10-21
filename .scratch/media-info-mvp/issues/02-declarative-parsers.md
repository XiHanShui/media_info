# 调研：容器格式能否用声明式规格表描述

Type: research
Status: resolved
Blocked by:

## Question

ISO base media（MP4/MOV）的 box、Matroska/WebM 的 EBML element、RIFF（WAV/AVI）的 chunk、FLAC 的 metadata block——这些结构**能否用一张声明式的规格表描述**，从而由一个通用引擎解析并渲染出树？还是每个格式只能各写各的命令式解析器？

要回答的：

- 这四种结构各自规整到什么程度？哪些是"固定布局 + 少量变长字段"，哪些本质上不规则？
- MP4 里 `stsd`/`esds`/`avcC` 这类"带子结构的字段"能否用同一张表表达？box 长度是 32 位还是 64 位（`largesize`/`co64`）对表结构的影响？
- EBML 的 VINT 编码、未知长度（unknown-size）、以及 element 的层级声明，能否用一张嵌套表描述？
- **Dart 生态里有没有现成的表驱动 / 声明式二进制解析库**？（查 pub.dev，看有没有能直接拿来用的；注意本仓库走 `pub.flutter-io.cn` 镜像。）
- 如果可行，这种表在 Dart 里大概长什么样——给出一个示意（哪怕只是伪代码），以便后续实现有据可依。

**依据**：ISO/IEC 14496-12、EBML 规范、Matroska 规范、RIFF 规范、FLAC 规范的原文，不要二手博客。

**产出**：`docs/research/02-declarative-parsers.md`，结论摘要回填本票 `## Answer`。

**为什么重要**：直接决定 MVP 的解析层是"写 N 个解析器"还是"写 N 张表 + 1 个引擎"。这条结论可能显著改变后续所有实现票的工作量。

## Answer

完整调研见 [docs/research/02-declarative-parsers.md](../../../docs/research/02-declarative-parsers.md)（664 行，一手来源：ISO/IEC 14496-12、RFC 8794、RFC 9559、RFC 9639、RIFF 规范、Matroska 官方 schema XML、pub.dev 上的包源码）。

**结论：声明式可行，但可行的是"结构树"这一层，不是"语义字段"这一层。**

| 格式 | 容器框架（层级/偏移/长度/子块） | 叶子载荷（块内字段语义） | 判定 |
|---|---|---|---|
| EBML / Matroska / WebM | 完全声明式——**规范自己就发布了机器可读的 schema 表** | 完全声明式 | 表已存在 |
| FLAC metadata blocks | 完全声明式——7 种 block，统一 4 字节头 | 声明式，需位域字段 + 一处小端例外 | 表很小 |
| RIFF（WAV / AVI） | 完全声明式——所有 chunk 同一套规则 | 开放：chunk type 无中心注册表 | 框架表极简 |
| ISO BMFF（MP4 / MOV） | 完全声明式——box 头统一，层级由规范 Table 1 枚举（88 种 box 类型，MP4RA 注册 282 个 ISO 家族码） | 混合：sample entry 动态、编解码扩展块在别的规范 | 结构表可行 |

**单一最重要的发现**：Matroska 的元素层级**已经以声明式 schema 表的形式公开发布**（`ebml_matroska.xml`，262 个元素 / 262 个唯一 ID / 49 个 master 元素），而且 pub.dev 上的 `ebml` 包把 RFC 8794 的 "EBML Schema" 实现成了 Dart 数据类 + 一个通用解码引擎。设想中的"表 + 通用引擎"路线，在 Matroska 上**既被规范验证过，也被 Dart 生态验证过**。

**第二条重要发现：Dart 生态没有可用的通用声明式二进制解析库。**

- `binstruct` 只有 8/16 位整数 + float32 + 嵌套 struct（查源码确认）——补齐 MP4/EBML/FLAC 所需能力等于重写，且无维护者、无 repository。
- Kaitai `.ksy` 在 pub.dev 上**没有 Dart 运行时**。
- `mediaindex_dart` 的 SDK 约束是 `<3.0.0`，**在本机 Dart 3.11.4 上根本 resolve 不下来**，实现也只是硬编码 map。

→ 实际路线：**自建一个小的 spec-table DSL + 一个通用引擎（约 300–500 行）**，以 `ebml` 包的 `SchemaElement` 字段设计为参考。

**建议的解析层形态（三层，不要二选一）**：

1. **规格表**（声明式数据）——每种格式一张表：MP4 的 box 表、Matroska 的 element 表、RIFF 的 chunk 表、FLAC 的 block 表。
2. **通用容器引擎**（代码，只写一次）——读头 → 查表 → 走字段 → 递归 → 产出统一节点。
3. **叶子提取器**（少量手写）——从已解析的树里取语义字段，每格式一个，不重复解析字节。

这个划分与既有前提天然对齐：结构树（偏移/长度/hex）由第 1+2 层产出，语义字段由第 3 层产出；而"语义字段只做到轨道级、不做编码参数级"这条约束，恰好让第 3 层保持很小。

**引擎必须支持的能力清单**（本次调研的主要工程产出）：32/64 位长度 + "size==0 延伸到 EOF"、变长整数（VINT）、unknown size + 基于路径的收尾判定、version 条件字段、24 位 flags、按前一字段决定后续数组宽度、计数前缀数组 / 嵌套记录、长度前缀字节串、**位域（bit-level）字段**、块内字节序切换、动态 type 分派 + 二级表、自描述尾部长度、"未知即跳过"兜底。

**各格式的"不规则点"**（必须留手写逃生口，不能只靠表）：

- **MP4 / MOV**——`stsd` 的 sample entry 类型是动态的（`avcC` 在 14496-15 而非 14496-12）；`stz2` 的位宽由载荷决定；`colr` 按 `colour_type` 分派变长载荷；`version`/`flags` 的位级含义属语义层。
- **EBML / Matroska**——`SimpleBlock`/`BlockGroup` 的 4 种 lacing 载荷不可表驱动（结构树里当不透明叶子即可）；unknown size 的收尾判定需要 schema 的路径信息；WebM 子集需在表里保留标记。
- **RIFF / WAV / AVI**——chunk type 无中心注册表，表只能是"通配 + 不透明"；`fmt ` 载荷是 tagged union 且带 `cbSize` 扩展，"扩展里是什么"必须按 tag 分派。
- **FLAC**——块载荷是**位域**而非字节字段（FLAC 独有的额外要求）；Vorbis comment 的长度字段是**小端**（FLAC 唯一的字节序例外）。

**共同好消息**：三种格式的规范都要求"未识别的类型必须被忽略并跳过"——这对通用引擎是天然兜底，**引擎永远能产出完整的结构树**，即使遇到没见过的扩展。手写解析器通常不会为未知块写兜底，而这对一个"要展示原始结构"的工具是刚需。

**既有前提的微调**：纯 Dart 不变；"每格式一个解析器"变成"每格式一张表 + 一个 extractor"，总量持平甚至更少。**"解析器注册表"扩展点的形状不变、粒度变细**——登记的应该是规格表 + 可选的叶子提取器，而不是解析器对象。

**不采用**：`binstruct`（能力不足且无维护）、直接依赖 `ebml` 包（形态对，但 2023-09 后未更新、只内置 EBML Header 表、不含 Matroska 表、描述里的 RFC 号是旧的——**但它的 `SchemaElement` 字段设计值得抄**）、Kaitai `.ksy`（无 Dart 运行时）、`mediaindex_dart`（SDK 约束过旧）。

**对下游票的影响**：

- [统一节点模型与双视图的数据来源](01-unified-node-model.md)：节点 schema 现在有了一个具体的消费方——**规格表的编译产物就是节点树，引擎的输出契约即节点模型**。
- [字节访问与大文件策略](06-byte-access-large-files.md)：引擎所需能力（64 位长度、VINT、unknown size）已经明确。
- 语义字段 extractor 的清单仍归[统一语义字段词表](08-field-vocabulary.md)管，不另开票。

**实现备注**（写进规格，不另开票）：Matroska 的 `ebml_matroska.xml` → Dart 表是机械转换，官方 XML 是唯一真相源；建议先做**纵切验证**——用最小表集实现 MP4 的 `moov → trak → mdia → minf → stbl → stsd`，确认 version 条件字段 + 动态 type 分派能在引擎里表达，再推广到其它三种格式。

