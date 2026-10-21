# 结构树视图 + hex 视图

Status: ready-for-agent
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
- 本票**只动** `lib/src/ui/` 下的新文件与右栏的装配位置；左栏（实现票 20）不要改。

**依赖说明**：若实现票 20 的右栏装配位置与本票预期不符，以 20 的实际代码为准，先适配再实现。
