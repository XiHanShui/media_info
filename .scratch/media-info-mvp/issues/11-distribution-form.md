# 分发形态与签名

Type: grilling
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
