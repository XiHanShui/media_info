# 真机验收：在 Windows 上把应用点一遍

Status: ready-for-agent
Blocked by: 24

## Question / 任务

**应用必须真的跑起来、被真的点过一遍**，而不是"编译通过、测试通过"就算完。这张票负责在真机上跑完整流程并留下证据。

**必读**：[规格](../spec.md) 的 52 条 User Stories —— 验收要逐条对照。

**产出**：

**（一）端到端集成测试**（`integration_test/`）：

- 用 `integration_test` 包 + `flutter drive` 在 **Windows 桌面**上跑真实应用（真实 exe、真实文件、真实手势）。
- 覆盖主流程：启动 → 打开文件（真实路径注入）→ 看到语义字段 → 看到结构树 → 展开一个块 → 看到 hex → 打开第二个文件开第二个标签 → 切换标签 → 复制字段值 → 导出 JSON。
- 覆盖异常流程：喂截断样本 → 看到错误提示**且**仍能看到已读到的部分结构；喂一个非媒体文件 → 看到"无法识别的格式"。
- 覆盖扩展名不一致：喂一个 `.wav` 后缀的 MP4 → 看到不一致提示。
- `flutter drive -d windows` 必须跑通并全绿。

**（二）截图工具**（`tool/screenshot.ps1`）：

- 在 Windows 上抓取**应用窗口**（不是整个屏幕）并保存 PNG。
- 用 .NET（`System.Drawing` 的 `CopyFromScreen` 配合窗口句柄与 `GetWindowRect`）实现；先按进程名 `media_info` 找窗口。
- 输出到 `build/screenshots/<name>.png`。

**（三）截图证据**：

- 对关键界面状态各截一张：主界面（左右分栏）、结构树展开、hex 面板、标签页多开、错误状态、扩展名不一致提示。
- 截图要能被人直接看懂（窗口在前景、尺寸合理）。

**约束**：

- 集成测试与单元测试**分开**：集成测试放 `integration_test/`，不与 `test/` 混。
- `flutter drive` 在本机需要 Visual Studio 的 C++ 桌面工具链（已装：VS Community 2026，`G:\Software\VS\T`）。
- 不新增重量级依赖；`integration_test` 是 Flutter SDK 自带的。
- `flutter analyze` 无 issue。
