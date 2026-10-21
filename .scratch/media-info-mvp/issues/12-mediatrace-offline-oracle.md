# 以 MediaTrace 作为结构树的离线校验基准

Type: grilling
Blocked by: 04

## Question

要不要把 MediaInfo 的 **MediaTrace XML** 当作我们结构树"有没有漏块"的**离线校验基准**？

背景见 [MediaInfo / ffprobe 到底能给出多深的结构](03-mediainfo-ffprobe-depth.md) 的结论：MediaInfo 的 MediaTrace 格式有官方 XSD 与样例（<https://mediaarea.net/mediatrace/mediatrace.xsd>），每块带 offset 与 size。它可以作为**对照工具**跑在 CI 里，不进产品二进制。

要定的：

- **要不要做**：做，还是不自己做对照基准？
- **怎么比对**：CI 里装 `mediainfo`，跑 `mediainfo --Details=1 --Output=XML <file>`，解析出 (offset, size) 集合，与我们解析器产出的结构树比对——**我们漏了哪些块**？比对需要一个映射层（MediaTrace 的语义名 ↔ 我们的原始 fourcc），这层映射本身是工作量。
- **收益边界**：这类"解析器一开始就漏了某个 box"的 bug，**用自己产的 golden 文件测不出来**——golden 也是我们自己产的，漏了就是两边一起漏。这是对照基准唯一真正独特的价值。
- **风险**：把基准建在别人的解读树上，等于把 MediaInfo 的缺陷也继承进来。MediaTrace 本身**不完整**——它只 trace 自己会走进去的容器盒（`stsd`/`avcC` 之类不会逐个列出），未知块走 default 分支被折叠。所以"MediaTrace 有、我们没有"并不总是我们错。**这个基准只单向可用：我们漏了它有的 → 我们错；它漏了我们有的 → 不一定。**
- **备选**：自己产 golden（把当前解析器输出当基准）。简单、零外部依赖，但如上所述发现不了"一开始就漏"的 bug。是否接受这个取舍？

**产出**：决定（采纳 / 不采纳 / 延后），若采纳则给出一套可执行的比对方案（谁在 CI 里跑、比什么、不一致时怎么报）。

**为什么阻塞于[测试素材获取与归档](04-test-fixtures.md)**：没有样本语料就没有可比对的基准，对照基准这件事无从谈起。素材落地后本票才可解。
