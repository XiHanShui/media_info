# 核心：节点模型 + 字节源 + 规格表 DSL + 通用容器引擎 + 注册表

Status: resolved
Blocked by:

## Question / 任务

实现解析层的**三层地基**（第 1、2 层）。**所有其它实现票都依赖本票的公开 API**，签名必须与 `docs/design/core-api.md` 完全一致。

**必读**：`docs/design/core-api.md`（强制契约）、[调研 02](../../docs/research/02-declarative-parsers.md) 第 3 节（引擎能力清单与 Dart 侧 DSL 草案）。

**产出**（`lib/src/core/`）：

- `node.dart` —— `ContainerNode`、`SemanticField`、`FieldOrigin`、`FieldScope`
- `byte_source.dart` —— `ByteSource` 抽象 + `FileByteSource`（`RandomAccessFile`，不整体读入内存）
- `spec.dart` —— `FieldType`、`FieldSpec`、`HeaderRule`、`ChildSpec`、`ContainerSpec`
- `engine.dart` —— `ParseResult`、`parseContainer(...)`
- `extractor.dart` —— `LeafExtractor` typedef
- `registry.dart` —— `FormatSpec`、`allFormats()`、`detectFormat(...)`
- `tag.dart` —— `Tag`、`collectTags(...)` 骨架（本票只放类型，具体格式的标签解析归实现票）
- `errors.dart` —— `TruncatedFile`

**引擎必须支持**：定长整数（大小端）、位域、fourcc、字节串（定长/由前字段决定长度）、UTF-8、布尔位、计数前缀数组、32/64 位长度、`size == 1` 的 64 位扩展、`size == 0` 到文件尾、VINT 长度与 VINT id、unknown size、动态 type 分派（`dispatchOn`）、**"未知即跳过"兜底**、递归深度上限（默认 64）。

**行为约定**：读到的字节少于声明长度 → 立即停止，`ParseResult.truncated = true`，`error` 给出中文说明，**已解析的部分照常返回**；引擎不向 UI 层抛异常。

**测试**（`test/core/`）：用 `test/fixtures/wav_pcm_s16le_44100_stereo.normal.wav` 之外的**内联字节**做引擎单测（自己造最小字节序列），覆盖：定长整数大小端、位域、VINT、`size == 1` 扩展、未知类型跳过、截断降级。

**约束**：纯 Dart 标准库，不新增 pub 依赖。`flutter analyze` 必须无 issue。

## Answer

已实现并合并进 `integration/media-info-mvp`。**8 个文件、1002 行实现 + 583 行测试**，是整个项目所有其它票的地基。

**公开 API 与契约一致**（见 `docs/design/core-api.md`），另有几处**增量**补充：

- `FieldSpec.length`——定长字节串的长度（契约里只有 `lengthFrom`「长度取自前一字段」，表达不了定长）。
- `HeaderRule.endian`（长度字段的字节序）+ `HeaderRule.sizeFirst`（size 字段排在 type 之前，ISO BMFF 是这个顺序）。RIFF（小端）和 MP4（size 在前）都需要。
- `parseContainer(..., {int maxDepth = kMaxRecursionDepth})`——递归深度上限的旋钮（默认 64）。

**集成期又补了两个口子**（都是并行开发暴露出来的）：

- `HeaderRule.prefixBytes`——容器载荷开头要跳过的字节数。**RIFF/AIFF/LIST 的载荷开头是 4 字节 form type（`WAVE`/`AIFF`/`INFO`），FLAC 是 `fLaC` 魔数**；不跳过的话引擎会把前缀当成子块头读，尺寸字段落在下一个块 id 上，报出假的"文件被截断"。见 `test/core/prefix_bytes_test.dart`。
- `FormatSpec.parser` + `parseFormat(spec, source, {depth})`——**调用方应该用的唯一入口**。有些格式装不进通用表（RIFF 的 form type、FLAC 的位域块头、MP3 根本没有块树），由格式模块自己提供解析函数接进来，调用方**不需要按格式分支**。

**其它要点**：

- `depth` 语义：`depth 1`（默认）建到根的第一层子块，`depth N` 建 N 层。**没有"增量展开单个节点"的 API**——要更深只能重解析。
- 根节点是整个文件（offset 0，size = 文件长度，type = `spec.rootType ?? spec.name`），spec 的 `header`/`children` 描述的是**根的子块**。
- 截断的块**仍留在树里**，size/dataSize 按实际可读字节裁剪，`isOpaque = true`。
- 引擎**不向 UI 层抛异常**，错误通过 `ParseResult.truncated` / `ParseResult.error`（中文）传达。
- `dispatchOn` 的查找顺序：先当前容器的 children map，再祖先容器（近的优先）；找不到就降级为不透明叶子（已读到的字段保留）。

**验证**：`flutter analyze` 无 issue；`flutter test` 全过；`dart format` 0 变更。
## Answer

已实现并合并进 `integration/media-info-mvp`。**8 个文件、1002 行实现 + 583 行测试**，是整个项目所有其它票的地基。

**公开 API 与契约一致**（见 `docs/design/core-api.md`），另有两处**增量**补充：

1. `FieldSpec.length`——定长字节串的长度（契约里只有 `lengthFrom`「长度取自前一字段」，表达不了定长）。
2. `HeaderRule.endian`（长度字段的字节序）+ `HeaderRule.sizeFirst`（size 字段排在 type 之前，ISO BMFF 是这个顺序）。契约里没写这两处，但 RIFF（小端）和 MP4（size 在前）都需要。
3. `parseContainer(..., {int maxDepth = kMaxRecursionDepth})`——递归深度上限的旋钮（默认 64）。

**集成期又补了两个口子**（都是并行开发暴露出来的）：

- `HeaderRule.prefixBytes`——容器载荷开头要跳过的字节数。**RIFF/AIFF/LIST 的载荷开头是 4 字节 form type（`WAVE`/`AIFF`/`INFO`），FLAC 是 `fLaC` 魔数**；不跳过的话引擎会把前缀当成子块头读，尺寸字段落在下一个块 id 上，报出假的"文件被截断"。见 `test/core/prefix_bytes_test.dart`。
- `FormatSpec.parser` + `parseFormat(spec, source, {depth})`——**调用方应该用的唯一入口**。有些格式装不进通用表（RIFF 的 form type、FLAC 的位域块头、MP3 根本没有块树），由格式模块自己提供解析函数接进来，调用方**不需要按格式分支**。

**其它要点**：

- `depth` 语义：`depth 1`（默认）建到根的第一层子块，`depth N` 建 N 层。**没有"增量展开单个节点"的 API**——要更深只能重解析。
- 根节点是整个文件（offset 0，size = 文件长度，type = `spec.rootType ?? spec.name`），spec 的 `header`/`children` 描述的是**根的子块**。
- 截断的块**仍留在树里**，size/dataSize 按实际可读字节裁剪，`isOpaque = true`。
- 引擎**不向 UI 层抛异常**，错误通过 `ParseResult.truncated` / `ParseResult.error`（中文）传达。
- `dispatchOn` 的查找顺序：先当前容器的 children map，再祖先容器（近的优先）；找不到就降级为不透明叶子（已读到的字段保留）。

**验证**：`flutter analyze` 无 issue；`flutter test` 全过；`dart format` 0 变更。
