# 应用级 widget 测试

Status: resolved
Blocked by: 20, 21, 22

## Question / 任务

实现**应用级接缝**的测试：启动真实应用，喂真实样本文件，断言渲染结果。

**必读**：[规格](../spec.md) 的 Testing Decisions 段（"什么样的测试算好"、两条接缝的分工）、[界面布局与多文件交互](07-ui-layout-prototype.md)。

**产出**（`test/app/`）：

- 用 `testWidgets` + `tester.pumpWidget(...)` 启动**真实**应用（不是 mock widget）。
- 通过应用暴露的注入点喂入样本文件路径（**不要**去模拟用户点文件选择器——那是系统对话框，测不了）。做法：应用允许构造时传入初始文件路径，或暴露一个可测试的"打开文件"入口。
- 断言：
  - 语义字段视图里出现了哪些字段与值（按中文显示名或英文 key 断言，二者选一并保持一致）。
  - 结构树里出现了哪些块类型。
  - 选中一个块后，hex 面板出现且内容非空。
  - 解析失败时（喂 `.truncated` 样本）：界面显示错误信息，且**仍能看到已读到的部分结构**。
  - 多标签页：打开两个文件后有两个标签，切换后内容随之改变。
- **删除脚手架自带的计数器冒烟测试**（`test/widget_test.dart`）——它断言的是模板的 `MyApp` / `MyHomePage`，应用重写后必然失效。

**约束**：

- 只用 `flutter_test`，不新增依赖。
- 断言外部可观察行为，不断言内部实现细节。
- `flutter analyze` 无 issue；`flutter test` 全绿。

## Answer

已实现并合并进 `integration/media-info-mvp`。**387 个测试全绿**（新增 28 个应用级测试）。

新增测试文件：

- `test/app/app_widget_test.dart` —— 应用级主流程：打开文件后字段视图出现哪些中文标签与值、结构树列出哪些顶层块、**选中块后 hex 面板出现且字节与文件里该偏移处的字节一致**、扩展名不符时横幅出现**且文件仍按实际格式解析**、截断文件不崩且仍显示能读到的字段、非媒体文件显示「无法识别的文件格式」、文件不存在时该标签页显示「文件不存在」**且不影响其它标签页**、多标签页切换。
- `test/app/export_json_document_test.dart` —— JSON 构造（纯函数）的结构：文件级 / 轨道级 / 标签分区、结构树递归、键顺序稳定、二进制标签值的确定性编码。
- `test/app/file_strip_test.dart` —— 胶片条：顶层块按比例成段、媒体载荷段与元数据段的样式不同、选中节点被高亮。

**关键测试手法**（本票确立的，后续票沿用）：

- 驱动应用用 `MediaInfoApp(initialPaths: [...])`——与 `MEDIA_INFO_OPEN_FILES` 环境变量同效，但进程内可设。
- **解析在 isolate 里跑**，所以 widget 测试必须先 `await tester.runAsync(...)` 再 `pumpAndSettle`，否则看到的永远是加载态。
- 结构树的行 key 是**基于路径**的（偏移会撞：根与第一个子块都在偏移 0）：`ValueKey('structure-row-<path>')`，path 是子节点下标链（`root`、`0`、`2`、`2.1`）。点 `structure-toggle-*` 展开/折叠，点 `structure-row-*` 选中。
- 测惰性展开要注入假的 loader：`loader: (path, {required depth}) async => deeperRoot`，断言它被以 **> 8 的深度**调用、之后新子节点出现。
- `resetToken`（一个会变的 int）重置展开与选中状态——"切标签页 ⇒ 重置"用它。
