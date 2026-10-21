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

## 验收记录（第一轮，应用骨架合并后）

用 `tool/acceptance.ps1` + `tool/screenshot.ps1`（`PrintWindow` 直渲窗口，不受遮挡影响）在真机上跑，逐张看图。截图存 `build/screenshots/`。

**已通过**：

| 场景 | 结果 |
|---|---|
| 打开 MP4 | 文件级 + 轨道级字段全对（`isom` / 1 s / `avc1` 320×240 25 fps / `mp4a` 44100 Hz 16 bit / 推算码率带「（推算）」标记） |
| 多个文件多标签页 | 三个标签页并存，互不影响 |
| **扩展名与实际格式不符** | 粉色横幅「⚠ 扩展名 `.wav` 与实际格式 `MP4` 不符」，**且照实际内容按 MP4 解析** |
| 非媒体文件 | 「无法识别的文件格式」+ 路径，不崩 |
| 截断的 MP4 | 优雅降级：文件级字段仍在，轨道级显示「没有轨道级字段」，不崩 |

**发现的三个问题**（前两个是功能缺口，第三个是显示问题）：

1. **截断的错误提示没有显示** —— 格式识别成功但 `truncated == true` 且 `error != null` 时，界面**任何地方都不渲染这个错误**（`document_tab.dart` 只处理了"识别不出来"和"打不开"两种；`app.dart` 只渲染扩展名横幅）。用户故事 48「遇到损坏或截断的文件时看到明确的错误说明」**未满足**。修法：在扩展名横幅旁边补一条截断/损坏警告。
2. **列表型字段被折叠成「（N 项）」** —— `compatible_brands` 显示「（4 项）」，`isom, iso2, avc1, mp41` 全丢了。这是真的信息损失：短列表的标量应当展开显示。
3. **文件名换行断在词中间** —— `mp4_h264_aac_320x240.norm` / `al.mp4`，且挤到下面的英文键名上。应省略号截断 + tooltip，或按词换行。
