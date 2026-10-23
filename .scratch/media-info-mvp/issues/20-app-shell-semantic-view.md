# 应用骨架：窗口 + 标签页 + 打开文件 + 语义字段视图

Status: resolved
Blocked by: 13

## Question / 任务

实现 Flutter 应用的骨架与左栏（语义字段视图）。

**必读**：[规格](../spec.md)（尤其 User Stories 1–16、41–43、46–47、51）、[界面布局与多文件交互](07-ui-layout-prototype.md)（布局已定案）、[统一语义字段词表](08-field-vocabulary.md)、`docs/design/core-api.md`。

**产出**（`lib/src/app/`）：

- `main.dart` 重写：启动应用，删除脚手架自带的计数器 demo（`MyApp` / `MyHomePage`）。
- **窗口骨架**：顶部标签页栏（每个标签 = 一个打开的文件）+ 工具条（打开文件 / 导出 JSON）；主体左右分栏；右栏下方是 hex 面板的位置（本票留空位或放占位，由实现票 21 填充）。
- **左栏 = 语义字段视图**，三个区段，顺序「文件级」→「轨道级」（每条轨道一组）→「标签」。区段之间用分隔线，不折叠。字段行显示：中文显示名 + 值 + 单位；**推算值（`origin == derived`）要有视觉区分**（例如标签文字加"（推算）"或用不同颜色）。
- **多标签页**：每个标签独立持有解析状态；`Ctrl+Tab` 切换；关闭标签不影响其它标签。
- **打开文件**：拖放（`DragTarget`）+ 文件选择器（`file_selector` 或 Flutter 桌面自带的文件选择 API——**先确认是否需要新依赖**，若需要新依赖，优先用平台通道自带的，避免引入重量级包）。
- **解析服务**（`lib/src/app/parse_service.dart`）：打开文件 → 嗅探格式 → 解析 → 产出 `ContainerNode` + 语义字段 + 标签 + 错误信息。**解析在 isolate 里跑**，别卡 UI。
- **文件注入点（真机验收与集成测试要用，必须实现）**：应用启动时读环境变量 `MEDIA_INFO_OPEN_FILES`（多个路径用分号 `;` 分隔），按顺序预打开这些文件并各开一个标签页。这是唯一的自动化入口——文件选择对话框是系统窗口，测不了、也点不了。变量不存在或为空时正常空启动。
- **状态**：解析中 / 解析成功 / 解析失败（失败时显示中文错误信息，**已读到的部分结构仍展示**）。

**格式判定与扩展名不一致（重要）**：

- 打开文件时**只信内容**：`detectFormat(source)` 决定实际格式，**扩展名不参与判定**。
- 界面显示**检测到的格式**（`container_format` 字段）。
- **扩展名与实际格式不符时，界面要明确提示**——例如一条 warning 条：「扩展名 `.wav` 与实际格式 `MP4` 不符」。是**提示不是报错**，解析照实际内容走。
- 扩展名**未知或缺失**（无扩展名）**不算**不一致，不提示。
- **完全不是媒体的文件**：`detectFormat` 返回 `null` → 显示"无法识别的文件格式"，不崩溃、不空白页。

判定逻辑写成**纯函数**方便单测（例如 `lib/src/app/extension_check.dart` 的 `checkExtension(String path, String? detectedFormat)` → 返回不一致提示文案或 `null`）。

**约束**：

- 界面文案**中文**；字段名、块类型名、codec 标识**保持英文**。
- 尽量不新增 pub 依赖；确需新增时先说明理由。
- `flutter analyze` 无 issue；`flutter test` 通过。

## Answer

已实现并合并进 `integration/media-info-mvp`。**287 个测试全绿**（新增 32 个，删掉脚手架的计数器冒烟测试），并且**应用真跑起来截图验证过**。

**新增依赖**：`file_selector: ^1.1.0`（flutter.dev 官方包，薄平台通道封装）。理由：Flutter 桌面**没有内置**文件选择器，而拖放路线无法被无头驱动。原生 registrant 是自动生成的，没有手改 `windows/flutter/generated_*`。

**公开 API**：

- `lib/src/formats/all_formats.dart`：`void registerAllFormats()`——调用五个 `register*` 函数。**注册顺序 = 嗅探顺序**（容器在前，MP3 的宽松匹配在后）。幂等，无 import 副作用。
- `lib/src/app/parse_service.dart`：`ParsedDocument`、`parseFile` / `parseFileInIsolate`（Isolate.run）、`parseStructureAtDepth`（票 21 的惰性展开入口）、`readOpenFilesFromEnvironment`。
- `lib/src/app/extension_check.dart`：`String? checkExtension(String path, String? detectedFormat)`——返回「扩展名 `.wav` 与实际格式 `MP4` 不符」；扩展名缺失/未知、或格式识别不出来时返回 `null`。
- `lib/src/app/semantic_view.dart`：`SemanticView`、`formatFieldValue`、`kDerivedSuffix = '（推算）'`。
- `lib/src/app/document_tab.dart`：`DocumentStatus`（loading/ready/failed）、`DocumentTab`、`DocumentTabBody`、`DocumentTabMessage`。
- `lib/src/app/app.dart`：`MediaInfoApp`、`AppShell`、`ExportJsonHandler` typedef、**`StructurePanePlaceholder`**（票 21 的槽位）。

**推算值的视觉区分**：中文标签用 `onSurfaceVariant` + *斜体*，标签后面另起一个 `tertiary` 色的「（推算）」chip；英文技术名显示在中文标签下方（`labelSmall` + 等宽字体），这样 widget 测试里 `find.text('采样率')` 和 `find.text('（推算）')` 都能命中。

**文件级字段的补齐**：按 UI 契约的规则——先**移除**提取器带来的同名 `file_name`/`file_size`/`container_format`（否则 Matroska 的 `file_size` 会重复出现），再统一塞入这三个。`container_format` 的值取自提取器已算好的结果（Matroska 的 DocType / MP4 的 `brand`），核心保持唯一真相源。

**票 21 的槽位**：`app.dart` 的 `AppShell._buildTabContent` 是装配点，右侧是 `DocumentTabBody(state: state, rightPane: const StructurePanePlaceholder())`。右栏行是 `Row[ Expanded(flex 1) = SemanticView, VerticalDivider, Expanded(flex 2) = rightPane ]`。

**给票 24 的提醒**：测试用 `MediaInfoApp(initialPaths: [...])` 驱动（与 `MEDIA_INFO_OPEN_FILES` 同效，但进程内可设）。解析在 isolate 里跑，所以 widget 测试必须先 `await tester.runAsync(...)` 再 `pumpAndSettle`。

**注意**：本票与实现票 21（结构树 + hex）会同时改 UI 目录。为避免冲突，本票只创建 `lib/src/app/` 下的骨架与左栏相关文件，**不创建结构树与 hex 相关的文件**。
