# golden 树快照

每个目标格式的 `.normal` 素材各一份**结构树快照**（JSON），用来防回归：
解析结果一旦变了，快照就对不上，测试会失败。

## 怎么重新生成

```powershell
dart run tool/gen_golden.dart
```

生成器在 `tool/gen_golden.dart`，序列化逻辑在 `test/support/golden_tree.dart`
（工具与测试共用同一份实现，保证「生成的」与「比对的」永远是同一套规则）。

**重新生成是逐字节稳定的**：键顺序固定、没有时间戳、没有绝对路径，
所以解析结果没变的时候重新跑一遍不会产生任何 git diff。

## 快照长什么样

```jsonc
{
  "format": "MP4",
  "fixture": "mp4_h264_aac_320x240.normal.mp4",
  "generator": "tool/gen_golden.dart",
  "notes": ["……"],
  "tree": {
    "type": "MP4",
    "offset": 0,
    "size": 11658,
    "dataOffset": 0,
    "dataSize": 11658,
    "isOpaque": false,
    "fields": [{ "key": "duration", "value": 1.0 }],
    "children": [ /* 递归 */ ]
  }
}
```

- 每个节点至少有 `type` / `offset` / `size` / `isOpaque` / `fields` / `children`；
  另外记了 `dataOffset` / `dataSize`（载荷区间）。
- `fields` 是 `{key, value}` 列表。
- **字节串**（`Uint8List`）渲染成 `hex:` 前缀的十六进制字符串
  （如 `hex:400EBB80000000000000`），不塞原始字节 —— 原始字节在 JSON 里不可读也不可 diff。

## 节点上限

每个节点最多记录 **64** 个子节点。超出的部分截断，并在该节点上多出
`childrenTruncated: true` 与 `childrenTotal: <总数>` 两个键。
这条限制主要是为 MP3 准备的：MP3 的结构树是**帧列表**（一帧一个节点），
长文件会有上千个帧节点，快照会变得又大又不可 diff。
本目录里的 MP3 样本只有 12 帧，没触发上限——这一点也写在快照的 `notes` 里。

## 与块覆盖率清单的关系

快照防的是**回归**，防不住「解析器从一开始就漏了某个块」——
快照也是我们自己产的，漏了就是两边一起漏。
「必须支持的块类型」由人写的**块覆盖率清单**负责
（`test/support/coverage_lists.dart`），清单的每一条都注明规范依据。
