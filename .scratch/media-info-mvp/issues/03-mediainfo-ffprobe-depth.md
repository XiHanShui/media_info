# 调研：MediaInfo / ffprobe 到底能给出多深的结构

Type: research
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
