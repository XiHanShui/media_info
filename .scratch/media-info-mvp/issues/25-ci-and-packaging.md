# CI 双平台构建 + zip 打包

Status: resolved
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

## Answer

已实现，合并进 `integration/media-info-mvp`。

**产出**：

- `.github/workflows/build.yml` —— 矩阵 `windows-latest` + `macos-latest`；`subosito/flutter-action` 钉死 Flutter `3.41.6` / `stable`；缓存 pub 包缓存与 Windows 的 CMake 构建目录（**分两次 cache**，因为 `actions/cache` 在任一列出的路径不存在时会拒绝保存整条）；**不设** `PUB_HOSTED_URL` / `FLUTTER_STORAGE_BASE_URL`；触发为 push 到 `main`、打 `v*` tag、手动 `workflow_dispatch`，**不在 PR 上跑**。步骤：pub get → analyze → test → release build → 打包 → 上传 artifact（保留 30 天）。版本号从 `pubspec.yaml` 读取，不硬编码。签名/公证在打包步骤前留了带注释的占位块。
- `tool/package_release.ps1`（Windows 友好，兼容 PowerShell 5.1 与 7+）与 `tool/package_release.sh`（POSIX，mode 755）—— 本地出同样的包，不依赖 CI。
- `.gitignore` 增加 `/dist/`。

**产物名**：`media_info-v1.0.0-windows-x64.zip`、`media_info-v1.0.0-macos-universal.tar.gz`。

**已验证**（本机实测）：`flutter build windows --release` 通过（48.8s 冷编译），`pwsh tool/package_release.ps1` 产出 11.09 MB 的 zip，内容含 `media_info.exe` + `flutter_windows.dll` + `data/`（app.so、icudtl.dat、flutter_assets）；`package_release.sh` 经 Git Bash 跑通且 `sh -n` 语法通过；YAML 经 `py -c "import yaml..."` 解析通过（15 步，矩阵与触发器符合预期）；`flutter analyze` 无 issue，`flutter test` 通过。

**未验证**：GitHub Actions 的真实运行（未推送）、真实的 macOS 构建（本机无 Mac，macOS 打包步骤只用 stub `.app` 试过）。

**已知偏差（不影响本 effort）**：产物名用 `-macos-universal` 是规格定的标签，但 `flutter build macos` 在 `macos-latest` 上产出的是**单架构** bundle（macos-14+ 为 arm64）。真要 universal 需要 `flutter build macos --universal` 或 lipo 合并——不在已定的票里，YAML 里留了注释说明。
