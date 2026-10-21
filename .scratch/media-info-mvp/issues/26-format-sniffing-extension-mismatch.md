# 跨格式嗅探一致性 + 非媒体文件处理

Status: ready-for-agent
Blocked by: 14, 15, 16, 17, 18, 20

## Question / 任务

**文件的实际格式由内容判定，扩展名只作提示。** 各个格式的 `detect` 回调由各自实现票完成（14–18），本票负责**跨格式的一致性**与**识别不出来时的行为**。

**必读**：[规格](../spec.md) 的 User Stories 53–54、`docs/design/core-api.md` 的 `registry.dart` 段。

**为什么单独一张票**：每个格式各自测自己的 `detect` 是不够的——真正的风险在**跨格式**：嗅探顺序不对（WAV 的 `RIFF` 会不会被别的格式抢走）、MP4 与 MOV 撞车、Matroska 与 WebM 撞车、以及根本不是媒体的文件。

**要做的**：

- **嗅探顺序**：注册顺序即嗅探顺序。确认没有歧义——两个 `detect` 都返回 true 时，先注册的赢。**必须断言**：每个格式的 `.normal` 素材都只被自己的 `detect` 命中（可以写一个测试逐个 format 检查 `detectFormat` 返回的就是它）。
- **MP4 与 MOV**：嗅探结果相同（都是 ISO BMFF）。统一报 `MP4`，但在语义字段里用 `ftyp` 的 brand 区分 `MP4` / `QuickTime`。**不要**为 MOV 单独注册一个格式项。
- **Matroska 与 WebM**：同理，统一报 `Matroska`，`container_format` 用 `docType` 区分 `matroska` / `webm`。
- **非媒体文件**：`detectFormat` 返回 `null`，应用显示"无法识别的文件格式"（界面文案由实现票 20 负责），**不崩溃、不空白**。

**测试**（`test/formats/detect_test.dart`）：

- 遍历所有已注册格式 → 用它的 `.normal` 素材断言 `detectFormat` 返回它。
- **扩展名不符**：把 `mp4_h264_aac_320x240.normal.mp4` 复制成 `mislabelled.wav` 放进 `Directory.systemTemp` 的临时目录 → 断言仍被检测为 MP4。测试后清理临时目录。
- **无扩展名**：复制成 `noextension` → 断言检测正确，且**不**算"扩展名不一致"。
- **非媒体**：写一个纯文本临时文件 → 断言 `detectFormat` 返回 `null`。

**约束**：

- 纯 Dart，无新依赖（`dart:io` 的 `Directory.systemTemp` 够用）。
- `flutter analyze` 无 issue。
