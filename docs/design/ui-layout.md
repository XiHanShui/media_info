# UI 层契约

> 与 `core-api.md` 同级别：**实现层的强制契约**。实现票 20（应用骨架 + 语义字段视图）、21（结构树 + hex）、22（导出）并行开发，靠本文件对齐。

术语依 `GLOSSARY.md`（容器 / 块 / 轨道 / 语义字段 / 结构树 / 标签）。

## 文件划分

```
lib/src/app/
  main.dart              —— 应用入口（替换脚手架的 main.dart）
  app.dart               —— 根 Widget：MaterialApp + 主题
  parse_service.dart     —— 打开文件 → 嗅探 → 解析 → 结果
  document_tab.dart      —— 一个标签页的状态与视图
  semantic_view.dart     —— 左栏：语义字段视图
  extension_check.dart   —— 纯函数：扩展名与实际格式是否不一致
  export.dart            —— JSON 导出 + 复制字段值
lib/src/ui/
  structure_tree.dart    —— 右栏：结构树视图
  hex_view.dart          —— 右栏下方：hex 视图
```

**归属**（不要越界改别人的文件）：

| 票 | 可以改 |
|---|---|
| 20 | `lib/src/app/**`、`lib/main.dart`、删除 `test/widget_test.dart` |
| 21 | `lib/src/ui/**`，以及 `lib/src/app/app.dart` 里右栏的装配位置 |
| 22 | `lib/src/app/export.dart`，以及 `lib/src/app/semantic_view.dart` 里的右键菜单 |

**共享文件的冲突处理**：若 21 或 22 需要改 20 的文件，**先合并 integration 分支拿到 20 的最新代码再改**，不要凭记忆改。

## 状态模型

```dart
/// 一个打开的文件（一个标签页）的解析结果。
class ParsedDocument {
  final String path;
  final String? detectedFormat;   // detectFormat 的结果（null = 无法识别）
  final ContainerNode? root;      // 结构树根节点
  final List<SemanticField> fileFields;
  final List<TrackFields> tracks;  // 轨道级字段
  final List<Tag> tags;
  final bool truncated;
  final String? error;             // 中文错误说明
  final String? extensionWarning;  // 扩展名与实际格式不一致的提示
}

class TrackFields {
  final int trackIndex;
  final List<SemanticField> fields;
}
```

**文件级字段的补齐规则（重要）**：

各格式的提取器吐出的文件级字段**并不一致**：

| 字段 | MP4 | Matroska | RIFF/AIFF | FLAC | MP3 |
|---|---|---|---|---|---|
| `file_name` | ✗ | ✗ | ✗ | ✗ | ✗ |
| `file_size` | ✗ | **✓** | ✗ | ✗ | ✗ |
| `container_format` | ✗（用 `brand` 代替） | **✓** | ✗ | ✗ | ✗ |

所以 **parse service 必须统一补齐** `file_name` / `file_size` / `container_format` 三个键，规则是：

1. 先从提取器结果里**按 key 移除**同名的已有字段（Matroska 会带来 `file_size` 和 `container_format`），
2. 再统一塞入这三个由 parse service 自己算出来的值。

**不能简单 append**——否则 Matroska 文档的 `file_size` 会出现两次。

`container_format` 的取值：MP4 用 `ftyp` 的 major brand（`isom` / `qt  ` / `mp42`…）——`qt  ` 意味着 QuickTime；Matroska 用 EBML 的 DocType（`matroska` / `webm`）；其它格式用格式名（`WAV` / `AIFF` / `FLAC` / `MP3`）。

**左栏三个区段**（顺序固定）：

1. **文件级** —— `fileFields`（`scope == FieldScope.file`）
2. **轨道级** —— 每条轨道一组，`trackIndex` 为标题（如「轨道 0」），组内是该轨道的字段
3. **标签** —— `tags`，key-value 形式，key 保留英文原名

**字段行的显示**：

- 左：中文显示名（`label`）
- 右：值（`value`）与单位（`unit`）
- **推算值**（`origin == FieldOrigin.derived`）必须有视觉区分——在标签后加「（推算）」或用次要颜色。不可省略：用户要能一眼分出文件里写的和我们算的。

## 布局

- 顶层：标签页栏 + 工具条
- 主体：`Row` 左右分栏，左 = 语义字段视图，右 = `Column`（结构树视图 + hex 面板）
- hex 面板在右栏**下方**，选中块时出现，可折叠；未选中时收起
- 选中块 → 该块在树中高亮 + hex 面板更新

## 扩展名不一致

```dart
/// 扩展名与实际格式不一致时的提示文案；一致或无法判断时返回 null。
String? checkExtension(String path, String? detectedFormat);
```

- 扩展名缺失或不是已知媒体扩展名 → 返回 `null`（不提示）
- 扩展名与检测到的格式不符 → 返回中文提示，例如「扩展名 `.wav` 与实际格式 `MP4` 不符」
- `detectedFormat` 为 `null`（无法识别）→ 返回 `null`（由"无法识别的文件格式"状态负责）

**纯函数，无 UI 依赖**，便于单测。

## 注入点

应用启动时读环境变量 `MEDIA_INFO_OPEN_FILES`（分号分隔的路径），逐个打开并各开一个标签页。

- 变量不存在或为空 → 正常空启动
- 路径不存在 → 该标签页显示"文件不存在"，**不影响其它标签页**
- 这是**唯一的自动化入口**（文件选择对话框是系统窗口，测不了）

## 标签

```dart
/// 按树的形状分派收集标签。
List<Tag> collectTags(ContainerNode root, {ByteSource? source});
```

**`source` 必须传。** 节点不携带字节（`ContainerNode` 只有偏移量），而每一种标签的载荷都要从字节里解码
（MP4 的 `data` box、Vorbis comment、ID3 帧体）。不传 `source` 会得到**空列表**——不是报错，是静默地没有标签。

**渲染规则**：

- `value is Uint8List` → 二进制值（如封面图），显示成「封面, 12.3 KB」之类；其余一律当文本。
- **key 原样显示**（`©nam` / `TITLE` / `TIT2`），不翻译、不美化。`©` 是 U+00A9。
- **重复 key 是正常的**（`covr` 可以有多个，一个 `data` box 一个标签）——渲染成列表，不要用 map。
- `source` 是 `ilst` / `VORBIS_COMMENT` / `ID3v2` 三者之一，可用作分组标签。
- FLAC 会多吐一个 `vendor`（编码器厂商串，键名 `vendor`），不是用户标签——不想显示就滤掉。
- 标签是**独立的区段**，排在轨道级之后，不混进语义字段列表。

## 界面文案

- 界面文案**中文**
- **字段名、块类型名、codec 标识保持英文**（`moov`、`fmt `、`ftyp`、`V_VP9`、`MPEG-1 Layer 3`）
- 常用文案：打开文件 / 导出 JSON / 复制 / 解析中 / 解析失败 / 无法识别的文件格式 / 文件不存在 / 推算
