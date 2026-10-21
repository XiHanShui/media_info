# 调研：容器格式能否用声明式规格表描述

Type: research
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
