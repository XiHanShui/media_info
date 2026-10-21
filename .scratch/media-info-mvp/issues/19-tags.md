# 标签提取：MP4 udta/ilst、FLAC Vorbis Comment、MP3 ID3v2

Status: resolved
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

## Answer

已实现并合并进 `integration/media-info-mvp`。

**唯一的契约变更**：`collectTags` 多了一个**可选命名参数** `source`（`ByteSource`）：

```dart
List<Tag> collectTags(ContainerNode root, {ByteSource? source});
```

原因：节点不携带字节（`ContainerNode` 只有偏移量），而每种标签的载荷都要从字节里解码。**不传 `source` 会得到空列表**——不是报错，是静默地没有标签。UI 契约已同步更新。

**各格式产出的 key**（**一律原样，不翻译**）：

| 格式 | 来源 | key | 值 |
|---|---|---|---|
| MP4 | `ilst` | `©nam`、`©ART`、`©alb`、`trkn`、`covr`… | 文本给 String；`covr` 封面给 `Uint8List`；`trkn`（iTunes 的 8 字节布局）渲染成 `"3/12"` |
| FLAC | `VORBIS_COMMENT` | `TITLE`、`ARTIST`、`ENCODER`… | String；另加一个 `vendor`（编码器厂商串） |
| MP3 | `ID3v2` | `TIT2`、`TPE1`、`TALB`… | String（只解文本帧 `T***`，除 `TXXX`） |

**值的类型域恰好是 `String | Uint8List | null`**——整数的 `data` type code（21/22）也渲染成十进制**字符串**，这样 UI 只需处理两种情况：`value is Uint8List` → 二进制，其余 → 文本。

**容错**：永不抛异常（每段都包了 `on Object catch`）。未知的 `data` type code 保留原始 `Uint8List`；解不出来的 item/帧直接跳过，其余标签照常产出。MP4 的 `meta` FullBox 检测是启发式的（首字节 == 0），QuickTime 风格的无 version/flags 的 `meta` 也支持。`data` 的 type 字段**两种编码都认**：规范式 `01 00 00 00` 与 ffmpeg 式 `00 00 00 01`（真实素材是后者）。ID3v2.3（普通整数帧长）与 2.4（syncsafe）都支持；v2.2 不产出标签；ID3v1 不在范围内。

**给 UI 的提醒**：重复 key 是正常的（`covr` 可以有多个，一个 `data` box 一个标签）——渲染成列表而不是 map。

**验证**：`flutter analyze` 无 issue；全量测试通过；新增 `test/formats/tags_test.dart`（21 个测试），覆盖真实素材（MP4 的 `©too`、FLAC 的 `encoder`、MP3 的 `TSSE`、WAV → 空）+ 合成字节文件（多标签 MP4、二进制 `covr`、`trkn`、畸形 `data` box、没有 `=` 的 Vorbis 条目、撒谎的长度字段、ID3v2.3/2.4、非文本帧、垃圾输入）。
