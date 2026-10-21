# 解析器级测试基座 + 块覆盖率清单

Status: resolved
Blocked by: 14, 15, 16, 17, 18

## Question / 任务

建立**解析器级接缝**的测试基座，并补齐各格式的**块覆盖率清单**。

**必读**：[规格](../spec.md) 的 Testing Decisions 段（两条接缝、块覆盖率清单的要求）、[测试素材获取与归档](04-test-fixtures.md)。

**产出**（`test/`）：

- **基座**（`test/support/fixture_paths.dart` 或类似）：定位 `test/fixtures/` 下的样本，按 `<格式>_<参数>.<类别>.<扩展名>` 命名约定提供查询helper。
- **块覆盖率清单**（`test/support/coverage_lists.dart` 或类似）：每个格式一份「必须支持的块类型集合」，例如
  - MP4：`ftyp`/`moov`/`trak`/`mdia`/`minf`/`stbl`/`stsd`/`mdat`/`free`/`skip`
  - Matroska：`Segment`/`Info`/`Tracks`/`TrackEntry`/`Video`/`Audio`
  - FLAC：`STREAMINFO`/`VORBIS_COMMENT`
  - WAV：`RIFF`/`fmt `/`data`
  - AIFF：`FORM`/`COMM`/`SSND`
  - MP3：帧节点
  每份清单**注明依据**（哪份规范/哪条 user story），方便后人核对。
- **覆盖断言**：解析样本后，遍历结构树，断言清单里的每个块类型都能找到。清单里允许标注"若样本中存在才检查"（例如 `uuid`）。
- **golden 树**（`test/golden/`）：为每个格式的 `.normal` 样本存一份结构树快照（JSON），用于防回归。**快照要可读、可 diff**——用缩进 JSON，字段顺序稳定。生成快照的脚本放 `tool/`。
- **截断与撒谎样本**的断言：解析 `.truncated` 与 `.liesize` 样本时，断言**不抛异常**、返回了部分结构、且 `ParseResult.truncated == true` 或 `error != null`。

**约束**：

- 只用 `flutter_test`（已随 `package:test` 传递依赖提供），**不新增依赖**。
- `flutter analyze` 无 issue；`flutter test` 全绿。

## Answer

已实现并合并进 `integration/media-info-mvp`。**256 → 277 个测试**（新增 71 个），**没有改动过任何 `lib/**` 代码**。

**共享助手**（`test/support/`）：

- `fixture_paths.dart`——按 `<格式>_<参数>.<类别>.<扩展名>` 解析素材名，`FixtureCategory`（normal/edge/truncated/liesize），`fixtureSource()`、`requireFixturePath(format, category)` 等。
- `coverage_lists.dart`——`BlockCoverage` / `BlockCoverageEntry`（每条带 `spec` 字段记规范出处）、`blockCoverageLists`、`collectBlockTypes`、`missingRequiredBlocks`。Matroska 的条目用**规范名**，断言时经 `matroskaElementName(id)` 把节点 type（`0x18538067`）换回来。
- `format_parsers.dart`——`kParseDepth = 8`、`parseFixtureFile` 等。
- `golden_tree.dart`——快照序列化，`kMaxGoldenChildren = 64`。

**块覆盖率清单**（每条标注规范依据）：WAV 的 `RIFF`/`fmt `/`data`（RIFF 规范）、AIFF 的 `FORM`/`COMM`/`SSND`（Apple AIFF 规范）、FLAC 的 `STREAMINFO`/`VORBIS_COMMENT`（RFC 9639 §8.2/§8.6）、MP3 的 `MPEG Audio Frame`（ISO/IEC 11172-3 §2.4.2.3）、MP4/MOV 的 8 个（ISO/IEC 14496-12 §4.2/§4.3/§8.1.2/§8.10）、Matroska 的 7 个（RFC 8794 §5.1、RFC 9559 §5.1–§5.3.1.7）。

**两个素材事实影响了"必查/可选"的划分**：MOV 素材里**没有 `free` 盒**（只有 QuickTime 专有的 `wide`）→ MOV 的 `free` 标可选、`wide` 标必查；`skip`/`uuid` 在所有 ffmpeg 素材里都不存在 → 两个清单里都标可选（它们的存在性由 `test/formats/isobmff_test.dart` 的合成字节用例覆盖）。

**Golden 快照**：`test/golden/` 下 8 份 JSON（wav 2.6KB … mov 47KB），由 `tool/gen_golden.dart` 生成，生成器与测试**共用同一份实现**。固定键顺序、`JsonEncoder.withIndent('  ')`、无时间戳、无绝对路径，有幂等测试。节点内容含 `type`/`offset`/`size`/`dataOffset`/`dataSize`/`isOpaque`/`fields`/`children`。二进制字段渲染成 `hex:` 前缀的大写十六进制串。

**集成期发现并修掉的一个真问题**：8 份快照在 Windows 上**全部对不上**——git 的 `core.autocrlf=true` 把检出的 LF 转成了 CRLF，而生成器产出 LF。修法：比对时归一化换行符，**并且**加了 `.gitattributes` 统一全仓的换行策略（根治）。
