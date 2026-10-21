# 分发形态与签名

Type: grilling
Status: resolved
Blocked by: 05

## Question

**用户最终拿到的是什么？**

要定的：

- **Windows**：
  - 免安装 zip（解压即用）——成本最低
  - Inno Setup 安装包（有开始菜单快捷方式、卸载入口）
  - MSIX（有自动更新，但签名要求高、进程封装受限）
  - 推荐哪个？（本工具是自用 + 开源，"解压即用"往往比安装包更合适）
- **macOS**：
  - `.app` 的 zip
  - `.dmg` 挂载镜像
  - 两者都绕不开 **Gatekeeper 的 quarantine 标记**——未公证的 app 双击会被拦，用户得右键打开或 `xattr -d com.apple.quarantine`。这个体验要不要在 MVP 就处理？（已划到范围外的是 notarization，但"未公证导致的拦截提示"是分发形态的一部分，需要在这里定）
- **签名与公证**：需要付费 Apple Developer 账号（人工申请）。已明确划到本 effort 之外——这里只需确认"确定不签"这个前提对 MVP 成立，还是需要把签名拉回来。
- **自动更新**：明确不做？还是留在 fog？

**产出**：MVP 的分发形态决定（Windows 一套 + macOS 一套，各写清楚产物长什么样、用户怎么装）。

**注意**：这票**不执行**打包，只定形态。真正把形态变成可分发产物的是[CI 双平台构建](10-ci-dual-platform.md) 的 CI。

## Answer

**双端都发 zip。**

- **Windows**：免安装 zip。用户解压即用，不写注册表、不装服务、无需管理员权限。对一个自用 + 开源工具，"解压即用"比安装包更合适。产物 = `flutter build windows --release` 的输出目录（`media_info.exe` + `data/` + `flutter_windows.dll`）整体打 zip。
- **macOS**：`.app` 目录打 zip（或 tar.gz），不做 `.dmg` 挂载镜像——`.dmg` 主要是为了拖拽安装体验，而未公证的 app 在 macOS 上本来就会遇到 Gatekeeper 拦截，做成 `.dmg` 并不改善这一点。
- **签名与公证**：**确定不进 MVP**。需要付费 Apple Developer 账号 + 人工申请 + Xcode 配置，且未公证的 app 用户仍需右键打开或 `xattr -d com.apple.quarantine`——与本 effort 的"自用优先、开源但不承诺支持"定位相称。已划到本 effort 之外，若将来要真正对外分发，单独开 effort。
- **自动更新**：**不做**。留在雾区。
- **Windows 侧也不做安装包**（Inno Setup / MSIX）：会引入额外的构建工具链与配置文件，收益对自用工具不匹配。

