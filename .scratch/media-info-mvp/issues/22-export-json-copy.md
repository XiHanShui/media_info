# 导出 JSON + 复制字段值

Status: ready-for-agent
Blocked by: 20

## Question / 任务

实现两件导出能力。

**必读**：[规格](../spec.md)（User Stories 16、41–43）。

**产出**（`lib/src/app/export.dart` 附近）：

- **复制字段值**：在语义字段视图里右键某个字段 → 复制它的值到剪贴板（`Clipboard.setData`）。值的格式化规则：数值直接用其字符串形式；时长格式化成 `HH:MM:SS.mmm`；带单位的字段复制时**不含单位**（单位在界面上单独显示）。
- **导出 JSON**：工具条上的「导出 JSON」→ 弹出保存对话框，写出当前标签页的结果。JSON **同时包含语义字段与结构树**：
  - 语义字段：按「文件级 / 轨道级 / 标签」分区，字段用**英文技术名**做 key，另附中文显示名。
  - 结构树：递归的节点数组，每项含 `type` / `offset` / `size` / `isOpaque` / `children`。
  - 字段的 `origin`（read / derived）要带上，别丢掉这个信息。
  - `codec` 等标识保持英文原样。
- JSON 用 `jsonEncode` + `JsonEncoder.withIndent('  ')`，键名顺序稳定（便于 diff 与版本管理）。

**约束**：

- 界面文案中文；JSON 里的键名**英文**。
- 保存对话框：优先用平台自带的文件选择 API（先确认是否需要新依赖）。
- `flutter analyze` 无 issue。
