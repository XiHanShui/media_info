# 标签提取：MP4 udta/ilst、FLAC Vorbis Comment、MP3 ID3v2

Status: ready-for-agent
Blocked by: 14, 15, 16, 18

## Question / 任务

实现**标签**（作者写进文件的元数据）的提取，产出统一的 `Tag` 列表。

**必读**：[标签 / 元数据与语义字段的边界](09-tag-vs-field-boundary.md)（术语与边界）、`docs/design/core-api.md` 的 `tag.dart` 段。

**要实现的**：

- **MP4**：`udta` → `meta`（注意 `meta` 是 FullBox，有 4 字节 version/flags 之后才是子元素）→ `ilst` → 若干 `©nam` / `©ART` / `©alb` / `trkn` / `covr` 等 item。每个 item 的载荷是 `data` box（type + locale + 字节）。`covr` 是二进制（JPEG/PNG）→ 值的类型要能表达二进制。
- **FLAC**：`VORBIS_COMMENT` 块 → vendor string + 若干 `KEY=VALUE` 对。**长度字段是小端**（与 FLAC 其它部分相反）。
- **MP3**：`ID3v2`（本 MVP 只支持 `ID3v2.3` / `ID3v2.4` 的文本帧 `T***`；`ID3v1` 也在尾部，顺手支持）。帧头 10 字节，帧体大小在 v2.3 是普通整数、v2.4 是 syncsafe 整数。

**共同要求**：

- 标签的 `key` **保留英文原名，不翻译**（`©nam` 就显示 `©nam`；Vorbis 的 `TITLE` 显示 `TITLE`；ID3 的 `TIT2` 显示 `TIT2`）。
- 统一产出 `List<Tag>`，每项有 `key`、`value`、`source`（来自哪个块）。
- 值可能是字符串、也可能是二进制（封面）→ `Tag.value` 的类型是 `Object?`，二进制用 `Uint8List`。
- **不认识的标签类型要跳过而不是报错**。

**测试**（`test/formats/tags_test.dart`）：素材里的 ffmpeg 默认不写标签，需要**在测试里现造**带标签的文件（用 `tool/gen_fixtures.dart` 同款手法写最小字节序列），断言能解出 key/value；再用真实素材断言"没有标签时返回空列表而不是崩"。

**约束**：纯 Dart，无新依赖。`flutter analyze` 无 issue。
