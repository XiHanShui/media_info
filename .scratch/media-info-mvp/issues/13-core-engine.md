# 核心：节点模型 + 字节源 + 规格表 DSL + 通用容器引擎 + 注册表

Status: ready-for-agent
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
