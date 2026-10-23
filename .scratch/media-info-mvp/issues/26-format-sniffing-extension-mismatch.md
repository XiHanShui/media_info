# 跨格式嗅探一致性 + 非媒体文件处理

Status: resolved
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

## Answer

已实现并合并进 `integration/media-info-mvp`。测试文件 `test/formats/detect_test.dart`（402 行，63 个断言）。

**断言的表**：24 个素材 × 3 条断言——① `detectFormat` 返回期望的格式名；② **所有 6 个 `detect` 回调中，认领这个文件的恰好只有它一个**；③ 没有任何两个格式会同时匹配同一个文件（与注册顺序无关）。

**嗅探顺序** = 注册顺序，`allFormats()` 断言为 `['WAV','AIFF','MP4','FLAC','Matroska','MP3']`。用"永远返回 true 的 stub 格式"证明了顺序真的决定胜负（注册在前它赢，注册在后真的 WAV 赢）。

**MP4 vs MOV / Matroska vs WebM**：各自只注册**一个**格式（断言 `allFormats()` 里没有 `MOV`/`QuickTime`/`WebM`）。区分靠语义字段：MP4 用 `brand`（`isom` vs `qt  `），Matroska 用 `container_format`（`Matroska` vs `WebM`，来自 EBML 的 DocType）。

**扩展名与非媒体**：把 MP4 复制成 `mislabelled.wav` → 仍检测为 MP4（内容说了算）；复制成无扩展名的 `noextension` → 仍检测为 MP4；纯文本文件 → `detectFormat` 返回 `null`。

**嗅探只读文件头**：用计数型 `ByteSource` 包装断言，每个格式、每个素材，**总读取字节 ≤ 16 且最远触达字节 ≤ 16**。实测 WAV/AIFF 读 8 字节、MP4/FLAC/Matroska 读 4、MP3 读 3–4。**没有任何 detect 读超过 12 字节。**

**票 26 揪出的真 bug（我已修）**：`_detectIsoBmff` 原先只检查偏移 4 是不是 `ftyp`——**传统 QuickTime（首块是 `moov`/`wide`/`mdat`）与分片 MP4（`styp`/`moof`/`sidx`）完全认不出来**，真实世界的 .mov 与 fMP4 会直接显示"无法识别的文件格式"。已改成**走顶层 box 链**（最多 8 个 box），并顺带修掉了"偏移 4 恰好是 `ftyp` 就认成 MP4"的假阳性。

长度校验的取舍：**声明长度超出文件末尾是允许的**——被截断的 MP4/MOV 极常见，不能因为文件短就否认它是 ISO base media。只拒两种荒谬值：小于 8（连块头都装不下）、以及 `0xFFFFFFFF`（在 ISO BMFF 里那不是"未知长度"，而是声明一个 4GB 的盒子）。

**一个仍存在的次要表面**：`detectMp3` 会把一个只有 3 字节、内容是 `ID3` 的文件认成 MP3。这是"只看魔数"的固有取舍，不阻塞。

**验证**：`flutter analyze` 无 issue；`flutter test` **185 个全过、零跳过**（我把那条记录限制的 skipped 测试改成了 4 条真断言：老式 QuickTime / 分片 MP4 / `wide` 块 / 荒谬长度的假 `ftyp`）。
