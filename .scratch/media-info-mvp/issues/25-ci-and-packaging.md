# CI 双平台构建 + zip 打包

Status: ready-for-agent
Blocked by:

## Question / 任务

实现 GitHub Actions 双平台构建与 zip 打包。

**必读**：[CI 双平台构建](10-ci-dual-platform.md)、[分发形态与签名](11-distribution-form.md)（两份都已定案，照做即可）。

**产出**：

- `.github/workflows/build.yml`：
  - 矩阵 `windows-latest` + `macos-latest`。
  - 用 `subosito/flutter-action` 装 Flutter，**版本钉死 `3.41.6`**、`channel: stable`。**不要用 `latest`**。
  - 缓存：pub 包缓存 + Flutter SDK 缓存；Windows 侧额外缓存 CMake 构建目录。
  - **不要设** `PUB_HOSTED_URL` / `FLUTTER_STORAGE_BASE_URL`（本机走的是中国镜像，CI 用官方源，保证本地与 CI 行为可比）。
  - 触发：push 到 `main`、打 tag、手动 `workflow_dispatch`。**不在 PR 上跑**。
  - 步骤：`flutter pub get` → `flutter analyze` → `flutter test` → `flutter build windows --release` / `flutter build macos --release`。
  - 打包：Windows 把 `build/windows/x64/runner/Release/` 打成 zip；macOS 把 `build/macos/Build/Products/Release/*.app` 打成 tar.gz。命名带版本号与平台：`media_info-v1.0.0-windows-x64.zip`、`media_info-v1.0.0-macos-universal.tar.gz`。
  - 作为 artifact 上传（保留期 30 天）。
  - macOS 产物**只保证构建成功**，不做自动冒烟。
  - 留一个注释标明将来的签名/公证步骤应加在哪里（本 effort 不做）。
- `tool/package_release.sh`（或 `.ps1`）：本地打同样的包，方便没开 CI 时手动出产物。

**验证**：本机跑一次 `flutter build windows --release` 确认能出 exe；zip 打包脚本能跑通。

**约束**：

- YAML 缩进用 2 空格。
- 不引入新依赖。
- `flutter analyze` 无 issue。
