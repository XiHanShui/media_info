# 解析器级测试基座 + 块覆盖率清单

Status: ready-for-agent
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
