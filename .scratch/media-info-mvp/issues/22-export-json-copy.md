# 导出 JSON + 复制字段值

Status: resolved
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

## Answer

已实现并合并进 `integration/media-info-mvp`。

**导出 JSON**（`lib/src/app/export.dart`）：工具条的「导出 JSON」→ 系统保存对话框 → 写出 JSON。**JSON 构造是纯函数**（`buildDocumentJson(document)`），所以可测、可复现。

顶层键：`tool` / `schemaVersion` / `path` / `format` / `truncated` / `error` / `extensionWarning` / `fileFields` / `tracks` / `tags` / `structure`。

- 语义字段按**文件级 / 轨道级 / 标签**分区；键是**英文技术名**，另附中文显示名；`origin`（read / derived）与单位都保留。
- 结构树递归：每个节点含 `type` / `offset` / `size` / `isOpaque` / `fields` / `children`。
- 标签的二进制值（如封面）以确定性方式编码，不把原始字节塞进 JSON。
- 键顺序稳定，导出之间可直接 diff。

**复制字段值**（在 `semantic_view.dart`）：右键字段行 → 「复制」菜单 → 值进剪贴板，并给出「已复制：…」提示。时长格式化成 `HH:MM:SS.mmm`；带单位的值复制时**不含单位**。

**依赖**：用已有的 `file_selector` 取保存位置，没有再加新依赖。

**整合期的插曲**：负责这票的 agent 中途因证书错误挂掉，但它的产出是完整的（`export.dart` + 两个测试文件 + 三处改动）。我把它的工作区验过（340 个测试全绿）后自己提交并合并，只改了一处 lint（测试里多余的 `dart:typed_data` 导入）。

**真机点验**：右键「时长」的行 → 弹出「复制」菜单（截图 `build/screenshots/act_04_copy.png`）。保存对话框是系统窗口，无法自动点，但 JSON 构造是纯函数，已单独验证：MP4 的导出结构根是 `MP4`，子块 `[ftyp, free, mdat, moov]`，JSON 约 82 KB。
