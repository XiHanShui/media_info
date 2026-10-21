# CI 双平台构建

Type: task
Blocked by: 05

## Question

GitHub Actions 上用什么矩阵同时构建 Windows 与 macOS？**具体产出什么 artifact**？怎么配缓存？

要落地的：

- **workflow 触发**：推 main / 打 tag / 手动触发？MVP 要不要在 PR 上跑（注意仓库当前还没有任何 PR 流程）？
- **矩阵**：`windows-latest` + `macos-latest`，两边的 Flutter 版本要**钉死**到与本机一致（3.41.6 stable / Dart 3.11.4），不要用 `latest`——本机装的是 `G:\SDK\flutter`，CI 上版本漂移会让构建结果不可复现。
- **产物**：Windows 侧 `flutter build windows` 产出的是一个目录（不是一个 exe），要打成 zip；macOS 侧 `flutter build macos` 产出 `.app` 目录，打成 tar.gz。命名要带版本号与平台。
- **缓存**：`pub` 的包缓存、Flutter SDK 缓存（用 `subosito/flutter-action`）、Windows 的 CMake 构建目录。
- **踩坑预防**：本机 pub 走的是 `pub.flutter-io.cn` 镜像——**CI 上不要**带这两个环境变量，用官方源，否则下载行为与本地不一致且可能更慢。
- **签名**：这一步先留空还是留占位（[分发形态与签名](11-distribution-form.md) 会定分发形态，macOS 签名/公证已划到本 effort 之外）？

**产出**：一个能跑的 workflow，push 上 main 并验证一次绿色。

**注意**：仓库是公开的 `XiHanShui/media_info`，`gh` 已登录，跑 CI 没有权限障碍。
