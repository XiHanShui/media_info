# 统一节点模型与双视图的数据来源

Type: prototype
Status: resolved
Blocked by:

## Question

语义字段与结构树，应该由**同一棵节点树**派生，还是两套彼此独立的模型？节点 schema 到底长什么样？

具体要定下来的：

- 节点携带哪些属性——名称、类型、偏移量、长度、子节点、字段值、原始字节？哪些是可选的？
- 语义字段挂在节点的哪一级——文件级、轨道级、还是块级？同一个字段会不会在多处重复出现？
- 未知/未解析的块在树里怎么表示——是节点的一个状态，还是干脆不出现？
- 结构树与语义字段视图，是同一棵树的两种投影，还是各自持有数据？

用 **mock 数据**做原型验证：在一条 throwaway 路由上把两种候选模型各自渲染成树，重点看"字段挂在哪一级"这件事讲不讲得通、界面能不能接受。

**产出**：一个被选定的节点模型定义 + 一句话判定理由（为什么是它，不是另一种）。

**注意**：本票结论是[字节访问与大文件策略](06-byte-access-large-files.md) 与[统一语义字段词表](08-field-vocabulary.md) 的前置，模型定错会连带影响字节访问策略和字段词表。

**先例（来自[MediaInfo / ffprobe 到底能给出多深的结构](03-mediainfo-ffprobe-depth.md)）**：块扫描器只需产出最小四元组——`type`（文件里字面的块类型名）+ `offset` + `size` + `children`。本票要解决的是这个四元组**之上**的两件事：语义字段怎么挂上去、双视图怎么从同一份数据派生。

**先例（来自[容器格式能否用声明式规格表描述](02-declarative-parsers.md)）**：节点模型现在有了**具体的消费方**——解析层改为"规格表 + 通用容器引擎 + 叶子提取器"三层后，**引擎的输出契约就是节点模型**（引擎读头 → 查表 → 走字段 → 递归 → 产出统一节点）。因此本票定的 schema 必须同时满足三件事：① 能表达结构树（名称/类型/偏移/长度/子节点）；② 能挂载语义字段；③ 能作为通用引擎的稳定输出契约被规格表编译产出。先例：块扫描器的最小四元组 `type + offset + size + children`。

## Answer

**判定：一棵节点树，两个视图都是它的投影。** 不建平行模型。

契约（实现必须照此落地，字段名是跨模块的公共接口）：

```dart
/// 结构树节点 = 容器里的一个块。
class ContainerNode {
  final String type;        // 文件里字面的块类型名，如 'moov'、'fmt '、'ftyp'
  final int offset;         // 块在文件中的字节偏移（含块头）
  final int size;           // 块总字节长度（含块头）
  final int dataOffset;     // 载荷起始偏移
  final int dataSize;       // 载荷字节长度
  final bool isOpaque;      // 未识别类型 / 不透明叶子（不递归）
  final List<ContainerNode> children;
  final List<SemanticField> fields; // 直接挂在这个节点上的字段
}

/// 语义字段 = 从容器结构解读出的技术属性。
class SemanticField {
  final String key;         // 英文技术名，如 'sample_rate'——代码标识符，与规范逐字对照
  final String label;       // 中文显示名，如 '采样率'
  final Object? value;
  final String? unit;       // 'Hz'、'bit'、'px'…
  final FieldOrigin origin; // read = 文件里直接写的；derived = 我们推算的
  final FieldScope scope;   // file = 文件级；track = 轨道级
  final int? trackIndex;    // scope == track 时的轨道序号
}
```

判定理由：

- 语义字段**挂节点上**，不另建平行模型 → 两个视图天然是同一棵树的两种投影，不存在两套数据不同步的可能。
- 文件级 / 轨道级视图 = 对树做**聚合**（按 `scope` 与 `trackIndex` 收集），而不是另存一份数据。
- 未知块不消失：`isOpaque = true` 的节点照样出现在结构树里，`offset`/`size` 照样有。
- 字段来源随字段一起带（`origin`）→ 界面能直接标注"推算值"，对应 user story 15。
- **节点不持有字节内容**，只持有 `offset`/`size`；hex 视图按需从文件读 → 大文件不爆内存（配合[字节访问与大文件策略](06-byte-access-large-files.md)的惰性展开）。

