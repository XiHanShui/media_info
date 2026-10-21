# 结构树视图 + hex 视图

Status: resolved
Blocked by: 13, 20

## Question / 任务

实现右栏的**结构树视图**与下方的 **hex 视图**。

**必读**：[界面布局与多文件交互](07-ui-layout-prototype.md)（布局已定案）、[统一节点模型与双视图的数据来源](01-unified-node-model.md)（节点契约）、`docs/design/core-api.md`。

**产出**（`lib/src/ui/`）：

- **结构树视图**（`structure_tree.dart`）：
  - 可展开的树，每行显示 `type` + `offset` + `size`。
  - **虚拟滚动**（`TreeView` + `ScrollablePositionedList`，或 Flutter 自带能处理大树的方案）——moov 里可能上万节点，必须流畅。
  - **惰性展开**：展开某个节点时才解析它的子块（依赖引擎的 `depth` 机制）。展开状态在切换标签时重置。
  - 选中节点时高亮，并通知 hex 面板更新。
  - 节点显示 `type` 用的**英文原名**（`moov`/`fmt `/`ftyp`），不翻译。
- **hex 视图**（`hex_view.dart`）：
  - 位于右栏**下方**，选中块时出现，可折叠。
  - 标题显示该块的 `type`、offset、size。
  - 内容是 hex + **ASCII 侧栏**。
  - 按需从文件读字节（节点只带 offset/size，不带内容）。
  - 大块要**分页/截断**（例如只显示前 N 字节 + "还有 M 字节"提示），不能一次读几 GB。

**约束**：

- 界面文案中文；技术名英文。
- `flutter analyze` 无 issue。

## Answer

已实现并合并进 `integration/media-info-mvp`，并在真机上点验过。

**公开 API**：`structureNodeLabel(type)`（`0x18538067` → `Segment`）、`StructureTree`、`HexView`、`StructurePane`、`hexDumpLines()`、`kDefaultStructureDepth = 8` / `kStructureDepthStep = 4` / `kMaxStructureDepth = 64` / `kDefaultHexByteLimit = 4096`。

**虚拟滚动**：树被拍平成"可见节点列表"（只展开的节点才进列表），用 `ListView.builder` + `itemExtent: 22` 渲染——只建屏幕上的行。

**惰性展开**：没有子块、且不是不透明叶子的节点显示 `+` 展开器。点它就调 `parseStructureAtDepth` 按 `当前深度 + 4`（上限 64）**重新解析**，行上转圈显示忙状态；更深的树被缓存、同路径节点被换入并展开；若加深后仍无子块，该节点被记为叶子、展开器消失。

**hex 分页**：最多读 4 KB（`kDefaultHexByteLimit`）——几 GB 的 `mdat` 永远不会被整个读进内存。标题给出 `type / 偏移 / 大小`，正文每行 16 字节 + ASCII 侧栏。超长块显示「仅显示前 4096 字节，还有 N 字节未显示」；截断文件按文件长度夹取并说明；文件打不开只提示，不抛。

**占比条**：每行右端 72 px 的轨道按 `size / fileSize` 填充，左边是百分比（小于 1% 保留一位小数）。

**真机点验**（见票 27）：点 `moov` 的箭头 → 惰性展开出 `mvhd`/`trak`/`trak`/`udta`；点 `mdat` 行 → hex 面板出现且 ASCII 栏直接读出块名；胶片条同步高亮。

**整合期我做的两件事**：① 视觉改造（暗色仪器面板、选中态改成"发丝边 + 一点底色"而不是整条琥珀横杠、坐标列用等宽数字）；② 胶片条用 `structureNodeLabel` 映射 Matroska 的十六进制 ID。agent 合并时取了集成分支的改造版并加回它的 hex 标题友好名修复，两边都在。
- 本票**只动** `lib/src/ui/` 下的新文件与右栏的装配位置；左栏（实现票 20）不要改。

**依赖说明**：若实现票 20 的右栏装配位置与本票预期不符，以 20 的实际代码为准，先适配再实现。
